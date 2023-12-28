
-- TODO: setup formatter

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
        require('jdtls').setup_dap({ hotcodereplace = 'auto' })

        vim.api.nvim_buf_set_keymap(0, 'n', 'gi', '<cmd>lua require("jdtls").organize_imports()<CR>', {noremap=true, silent=true})
        vim.api.nvim_buf_set_keymap(0, 'n', '<leader>tc', '<cmd>lua require("jdtls").test_class()<CR>', {noremap=true, silent=true})
        vim.api.nvim_buf_set_keymap(0, 'n', '<leader>tm', '<cmd>lua require("jdtls").test_nearest_method()<CR>', {noremap=true, silent=true})
        vim.api.nvim_buf_set_keymap(0, 'n', '<leader>js', '<cmd>lua require("jdtls").jshell()<CR>', {noremap=true, silent=true})
    end
}

require('jdtls').start_or_attach(config)

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

            if capture then
                to_return = capture
            end

            coroutine.resume(co, to_return)
        end
    end)
end

-- run (or debug) gradle tests by method or class
local function runGradleTests(debug)
    local co = coroutine.create(function(class_or_method)
        print(class_or_method)

        local command = 'split term://./gradlew test'

        if class_or_method then
            command = command .. ' --tests "' .. class_or_method .. '"'
        end

        if debug then
            command = command .. ' --debug-jvm'
        end

        vim.cmd(command)
    end)

    extractTestFilterFromLsp(co)
end

function RunGradleTests()
    runGradleTests(false)
end

function DebugGradleTests()
    runGradleTests(true)
end

vim.api.nvim_create_user_command('RunGradleTests', RunGradleTests, {})
vim.api.nvim_create_user_command('DebugGradleTests', DebugGradleTests, {})

