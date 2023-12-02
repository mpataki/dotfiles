local root_markers = {'gradlew', '.git'}
local root_dir = require('jdtls.setup').find_root(root_markers)
local home = os.getenv('HOME')
local workspace_folder = home .. "/.local/share/eclipse/" .. vim.fn.fnamemodify(root_dir, ":p:h:t")

local config = {
    cmd = {
        '/opt/homebrew/Cellar/openjdk/20.0.1/bin/java',

        '-Declipse.application=org.eclipse.jdt.ls.core.id1',
        '-Dosgi.bundles.defaultStartLevel=4',
        '-Declipse.product=org.eclipse.jdt.ls.core.product',
        '-Dlog.protocol=true',
        '-Dlog.level=ALL',
        '-Xmx1g',
        '--add-modules=ALL-SYSTEM',
        '--add-opens', 'java.base/java.util=ALL-UNNAMED',
        '--add-opens', 'java.base/java.lang=ALL-UNNAMED',

        '-javaagent:' .. home .. '/.local/share/jars/lombok-1.18.22.jar',

        '-jar', '/opt/homebrew/Cellar/jdtls/1.29.0/libexec/plugins/org.eclipse.equinox.launcher_1.6.500.v20230717-2134.jar',

        '-configuration', '/opt/homebrew/Cellar/jdtls/1.29.0/libexec/config_mac_arm',
        '-data', workspace_folder
    },
    root_dir = root_dir,
    init_options = {
        bundles = { -- integrate java-debug
        vim.fn.glob(home .. "/.local/share/jars/com.microsoft.java.debug.plugin-0.50.0.jar", 1)
    };
},
settings = {
    signatureHelp = { enabled = true },
    java = {
        configuration = {
            runtimes = {
                {
                    name = "JavaSE-11",
                    path = "/opt/homebrew/Cellar/openjdk@11/11.0.19/libexec/openjdk.jdk/Contents/Home"
                },
                {
                    name = "JavaSE-17",
                    path = "/opt/homebrew/Cellar/openjdk@17/17.0.7/libexec/openjdk.jdk/Contents/Home"
                },
                {
                    name = "JavaSE-20",
                    path = "/opt/homebrew/Cellar/openjdk/20.0.1/libexec/openjdk.jdk/Contents/Home"
                }
            }
        },
    }
},
on_attach = function(client, bufnr)
    require('jdtls').setup_dap()
    require('dap.ext.vscode').load_launchjs("./launch.json")

    -- require('jdtls.dap').setup_dap_main_class_configs()
    -- require('jdtls').test_class()
    -- require('jdtls').test_nearest_method()


    local mapper = function(mode, key, result)
        vim.api.nvim_buf_set_keymap(0, mode, key, result, {noremap=true, silent=true})
    end

    mapper('n', 'gi',   '<cmd>lua require("jdtls").organize_imports()<CR>')
end
}

require('jdtls').start_or_attach(config)

