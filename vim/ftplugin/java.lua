local home = os.getenv('HOME')
local root_dir = require('jdtls.setup').find_root({'gradlew', '.git'})
local workspace_folder = home .. "/.local/share/eclipse/" .. vim.fn.fnamemodify(root_dir, ":p:h:t")

local cmd = {
    vim.fn.glob("/opt/homebrew/Cellar/openjdk/21.*/bin/java", true),

    '-Declipse.application=org.eclipse.jdt.ls.core.id1',
    '-Dosgi.bundles.defaultStartLevel=4',
    '-Declipse.product=org.eclipse.jdt.ls.core.product',
    '-Dlog.protocol=true',
    '-Dlog.level=ALL',
    '-Xmx1g',
    '--add-modules=ALL-SYSTEM',
    '--add-opens', 'java.base/java.util=ALL-UNNAMED',
    '--add-opens', 'java.base/java.lang=ALL-UNNAMED',

    '-javaagent:' .. home .. '/.local/share/jars/lombok.jar',

    '-jar', vim.fn.glob('/opt/homebrew/Cellar/jdtls/*/libexec/plugins/org.eclipse.equinox.launcher_*.jar', true),

    '-configuration', vim.fn.glob('/opt/homebrew/Cellar/jdtls/*/libexec/config_mac_arm', true), -- notice this is mac specific at the moment
    '-data', workspace_folder
}

local bundles = {
    vim.fn.glob(home .. "/.local/share/nvim/mason/packages/java-debug-adapter/extension/server/com.microsoft.java.debug.plugin-*.jar", true),
};

vim.list_extend(bundles, vim.split(vim.fn.glob(home .. "/.local/share/nvim/mason/packages/java-test/extension/server/*.jar", true), "\n"))

local config = {
    cmd = cmd,
    root_dir = require('jdtls.setup').find_root({'gradlew', '.git', 'mvnw'}),
    init_options = {
        bundles = bundles
    },
    settings = {
        signatureHelp = { enabled = true },
        java = {
            configuration = {
                runtimes = {
                    {
                        name = "JavaSE-11",
                        path = vim.fn.glob("/opt/homebrew/Cellar/openjdk@11/11.*/libexec/openjdk.jdk/Contents/Home", true)
                    },
                    {
                        name = "JavaSE-17",
                        path = vim.fn.glob("/opt/homebrew/Cellar/openjdk@17/17.*/libexec/openjdk.jdk/Contents/Home", true)
                    },
                    {
                        name = "JavaSE-20",
                        path = vim.fn.glob("/opt/homebrew/Cellar/openjdk/20.*/libexec/openjdk.jdk/Contents/Home", true)
                    },
                    {
                        name = "JavaSE-21",
                        path = vim.fn.glob("/opt/homebrew/Cellar/openjdk/21.*/libexec/openjdk.jdk/Contents/Home", true)
                    }
                }
            },
            completion = {
                favoriteStaticMembers = {
                    "org.hamcrest.MatcherAssert.assertThat",
                    "org.hamcrest.Matchers.*",
                    "org.hamcrest.CoreMatchers.*",
                    "org.junit.jupiter.api.Assertions.*",
                    "java.util.Objects.requireNonNull",
                    "java.util.Objects.requireNonNullElse",
                    "org.mockito.Mockito.*"
                },
            },
        }
    },
    on_attach = function(client, bufnr)
        client.server_capabilities.semanticTokensProvider = nil

        require('jdtls').setup_dap({ hotcodereplace = 'auto' })

        vim.api.nvim_buf_set_keymap(0, 'n', 'gi', '<cmd>lua require("jdtls").organize_imports()<CR>', {noremap=true, silent=true})
        vim.api.nvim_buf_set_keymap(0, 'n', '<leader>tc', '<cmd>lua require("jdtls").test_class()<CR>', {noremap=true, silent=true})
        vim.api.nvim_buf_set_keymap(0, 'n', '<leader>tm', '<cmd>lua require("jdtls").test_nearest_method()<CR>', {noremap=true, silent=true})
        vim.api.nvim_buf_set_keymap(0, 'n', '<leader>js', '<cmd>lua require("jdtls").jshell()<CR>', {noremap=true, silent=true})
    end
}

require('jdtls').start_or_attach(config)

-- map '.' preceeding @Nested class names with to "\$"
local function mapSymbolNameToTestFilterPattern(symbol)
    local result = ""
    local saw_first_class = false

    for token in string.gmatch(symbol, "(%w+).?") do
        local to_add = "."

        if string.match(token, "^%u") then
            if not saw_first_class then
                saw_first_class = true
            else
                to_add = '$'
            end
        end

        result = result .. to_add .. token
    end

    -- strip leading "."
    result = string.sub(result, 2, -1)

    return result
end

-- query the LSP for the class or method under the cursor
local function extractTestFilterFromLsp(co)
    local params = vim.lsp.util.make_position_params()
    vim.lsp.buf_request(0, 'textDocument/hover', params, function(err, result, ctx, config)
        if err then
            print("Error: " .. err)
            return
        end

        if result and result.contents then
            local contents = result.contents

            if type(contents) == 'table' then
                contents = contents.value or contents[1].value
            end

            -- parse out the method name or fall back to the class name,
            --   depending on what's under the cursor
            local to_return = contents

            local pattern = "%s([^%s]+)%("
            local capture = string.match(contents, pattern)

            if capture ~= nil then
                to_return = capture
            end

            to_return = mapSymbolNameToTestFilterPattern(to_return)

            coroutine.resume(co, to_return)
        end
    end)
end

local function startTerm(command)
    vim.cmd('tabedit term://' .. command)

    -- set the command in a buf var so we can easily restart it
    local bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_var(bufnr, 'terminal_command', command)
end

local function sendSigtermToTerminal(bufnr)
    -- Ensure the buffer is a valid terminal
    if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_option(bufnr, 'buftype') == 'terminal' then
        -- Get the job ID
        local job_id = vim.api.nvim_buf_get_var(bufnr, 'terminal_job_id')

        if job_id then
            -- Send SIGTERM to the job
            vim.fn.jobstop(job_id)
        else
            print("No job ID found for buffer " .. bufnr)
        end
    else
        print("Buffer " .. bufnr .. " is not a terminal")
    end
end

function RestartTerm()
    if vim.bo.buftype == 'terminal' then
        local bufnr = vim.api.nvim_get_current_buf()
        local command = vim.api.nvim_buf_get_var(bufnr, 'terminal_command')

        -- kill any running process
        sendSigtermToTerminal(bufnr)

        -- Close the current terminal buffer
        vim.api.nvim_buf_delete(0, { force = true })

        startTerm(command)
    end
end

-- run (or debug) gradle tests by method or class
local function runGradleTests(debug)
    local co = coroutine.create(function(test_filter)
        local command = './gradlew test --rerun'

        if test_filter ~= nil and test_filter ~= "" then
            command = command .. " --tests '" .. test_filter .. "'"
        end

        if debug then
            command = command .. ' --debug-jvm'
        end

        startTerm(command)
    end)

    extractTestFilterFromLsp(co)
end

function GradleRunTests()
    runGradleTests(false)
end

function GradleDebugTests()
    runGradleTests(true)
end

-- TODO: this should go into a boot-specific module
function RunBoot()
    startTerm('SPRING_PROFILES_ACTIVE=dev ./gradlew bootRun')
end

function DebugBoot()
    startTerm('SPRING_PROFILES_ACTIVE=dev ./gradlew bootRun --debug-jvm')
end

function GradleBuild()
    startTerm('./gradlew clean build -xtest')
end

-- default debugger attachment
require('dap').configurations.java = {
    {
        type = "java",
        request = "attach",
        hostName = "127.0.0.1",
        port = "5005"
    }
}

vim.api.nvim_create_user_command('GradleRun', GradleBuild, {})
vim.api.nvim_create_user_command('GradleRunTests', GradleRunTests, {})
vim.api.nvim_create_user_command('DebugGradleTests', GradleDebugTests, {})
vim.api.nvim_create_user_command('RunBoot', RunBoot, {})
vim.api.nvim_create_user_command('DebugBoot', DebugBoot, {})
vim.api.nvim_create_user_command('RestartTerm', RestartTerm, {})

vim.keymap.set('n', '<Leader>gb', GradleBuild)
vim.keymap.set('n', '<Leader>gt', GradleRunTests)
vim.keymap.set('n', '<Leader>gT', GradleDebugTests)
vim.keymap.set('n', '<Leader>gr', RunBoot)
vim.keymap.set('n', '<Leader>gR', DebugBoot)
vim.keymap.set({'n','t'}, '<Leader>r', RestartTerm)

