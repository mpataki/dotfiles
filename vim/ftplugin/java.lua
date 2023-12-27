
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
