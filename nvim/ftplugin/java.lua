local home = os.getenv('HOME')
local root_dir = require('jdtls.setup').find_root({'gradlew', '.git'})
local workspace_folder = home .. "/.local/share/eclipse/" .. vim.fn.fnamemodify(root_dir, ":p:h:t")

-- used to print tables like print(inspect(my_table))
-- local inspect = require('vim.inspect')

local cmd = {
    vim.fn.glob("/opt/homebrew/Cellar/openjdk@21/21.*/bin/java", true),

    '-Declipse.application=org.eclipse.jdt.ls.core.id1',
    '-Dosgi.bundles.defaultStartLevel=4',
    '-Declipse.product=org.eclipse.jdt.ls.core.product',
    '-Dlog.protocol=true',
    '-Dlog.level=WARN',
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
        -- First set up the common LSP keybindings
        if _G.setup_lsp_keybindings then
            _G.setup_lsp_keybindings(bufnr)
        end

        client.server_capabilities.semanticTokensProvider = nil

        -- note that jdtls is taking over the gq command, which usually drives formating, and I don't know how to make it stop...
        -- Here I'm basically rebuilding it so I can get full-file formatting
        vim.api.nvim_create_user_command('FormatBuffer', function()
            vim.cmd('execute "%!' .. vim.bo.formatprg .. '"')
        end, {})
        vim.keymap.set('n', 'gf', ':FormatBuffer<CR>', { noremap = true, silent = true })

        -- require('jdtls').setup_dap({ hotcodereplace = 'auto' })

        -- Java-specific keybinding: override 'gi' for organize imports
        vim.api.nvim_buf_set_keymap(0, 'n', 'gi', '<cmd>lua require("jdtls").organize_imports()<CR>', {noremap=true, silent=true})
        -- vim.api.nvim_buf_set_keymap(0, 'n', '<leader>tc', '<cmd>lua require("jdtls").test_class()<CR>', {noremap=true, silent=true})
        -- vim.api.nvim_buf_set_keymap(0, 'n', '<leader>tm', '<cmd>lua require("jdtls").test_nearest_method()<CR>', {noremap=true, silent=true})
        vim.api.nvim_buf_set_keymap(0, 'n', '<leader>js', '<cmd>lua require("jdtls").jshell()<CR>', {noremap=true, silent=true})

        -- align on google's formatter
        vim.opt_local.tabstop = 2
        vim.opt_local.softtabstop = 2
        vim.opt_local.shiftwidth = 2
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

local function executeViaVimux(command)
    vim.cmd("VimuxRunCommand \"" .. command .. "\"")
end

-- run (or debug) gradle tests by method or class
local function runGradleTests(debug)
    local co = coroutine.create(function(test_filter)
        local command = './gradlew test --rerun --info'

        if test_filter ~= nil and test_filter ~= "" then
            command = command .. " --tests '" .. test_filter .. "'"
        end

        if debug then
            command = command .. ' --debug-jvm'
        end

        -- StartTerm(command)
        executeViaVimux(command)
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
    local command = 'SPRING_PROFILES_ACTIVE=local ./gradlew bootRun'
    -- StartTerm(command)
    executeViaVimux(command)
end

function DebugBoot()
    local command = 'SPRING_PROFILES_ACTIVE=local ./gradlew bootRun --debug-jvm'
    -- StartTerm(command)
    executeViaVimux(command)
end

function GradleBuild()
    local command = './gradlew clean build'
    -- StartTerm(command)
    executeViaVimux(command)
end

function GradleCompileJava()
    local command = './gradlew compileJava && ./gradlew compileTestJava'
    -- StartTerm(command)
    executeViaVimux(command)
end

-- default debugger attachment
require('dap').configurations.java = {
    {
        type = "java",
        request = "attach",
        name = "Debug (attach) - Remote",
        hostName = "127.0.0.1",
        port = "5005"
    }
}

vim.api.nvim_create_user_command('GradleBuild', GradleBuild, {})
vim.api.nvim_create_user_command('GradleRunTests', GradleRunTests, {})
vim.api.nvim_create_user_command('DebugGradleTests', GradleDebugTests, {})
vim.api.nvim_create_user_command('RunBoot', RunBoot, {})
vim.api.nvim_create_user_command('DebugBoot', DebugBoot, {})
vim.api.nvim_create_user_command('GradleCompileJava', GradleCompileJava, {})

vim.keymap.set('n', '<Leader>gb', GradleBuild)
vim.keymap.set('n', '<Leader>gt', GradleRunTests)
vim.keymap.set('n', '<Leader>gT', GradleDebugTests)
vim.keymap.set('n', '<Leader>gr', RunBoot)
vim.keymap.set('n', '<Leader>gR', DebugBoot)
vim.keymap.set('n', '<Leader>gc', GradleCompileJava)

