return {
    { 'jay-babu/mason-nvim-dap.nvim' },
    { 'nvim-telescope/telescope-dap.nvim' },
    -- { -- TODO: try this guy out
    --     'stevearc/overseer.nvim',
    --     opts = {},
    --     config = function()
    --         require('overseer').setup()
    --     end
    -- },
    {
        'mfussenegger/nvim-dap',
        dependencies = {
            'nvim-neotest/nvim-nio',
            'rcarriga/nvim-dap-ui',
        },
        config = function()
            require('dapui').setup()

            vim.fn.sign_define('DapBreakpoint', {text='⚈', texthl='', linehl='', numhl=''})
            vim.fn.sign_define('DapStopped', {text = '→', texthl = '', linehl = 'Search', numhl = ''})

            vim.keymap.set('n', '<Leader>dc', function() require('dap').continue() end)
            -- vim.keymap.set('n', '<Leader>dO', function() require('dap').step_out() end)
            vim.keymap.set('n', '<Leader>di', function() require('dap').step_into() end)
            vim.keymap.set('n', '<Leader>do', function() require('dap').step_over() end)
            vim.keymap.set('n', '<Leader>db', function() require('dap').toggle_breakpoint() end)
            vim.keymap.set('n', '<Leader>dr', function() require('dap').run_last() end)
            vim.keymap.set('n', '<Leader>dt', function() require('dap').terminate() end)
            vim.keymap.set('n', '<Leader>dk', function() require('dap').up() end)
            vim.keymap.set('n', '<Leader>dj', function() require('dap').down() end)
            vim.keymap.set('n', '<Leader>df', function() require('dap').focus_frame() end)
            vim.keymap.set('n', '<Leader>lp', function() require('dap').set_breakpoint(nil, nil, vim.fn.input('Log point message: ')) end)

            vim.keymap.set({'n', 'v'}, '<Leader>dh', function()
                require('dap.ui.widgets').hover()
            end)

            vim.keymap.set({'n', 'v'}, '<Leader>dp', function()
                require('dap.ui.widgets').preview()
            end)

            vim.keymap.set('n', '<Leader>df', function()
                local widgets = require('dap.ui.widgets')
                widgets.centered_float(widgets.frames)
            end)

            vim.keymap.set('n', '<Leader>ds', function()
                local widgets = require('dap.ui.widgets')
                widgets.centered_float(widgets.scopes)
            end)

            vim.keymap.set('n', '<Leader>dr', function()
                require('dap').repl.open()
            end)

            vim.keymap.set({'n', 'v'}, '<Leader>du', function()
                require("dapui").toggle()
            end)

            require('telescope').load_extension('dap')

            local dap = require('dap')

            dap.adapters['pwa-node'] = {
                type = "server",
                host = "localhost",
                port = "${port}",
                executable = {
                    command = "js-debug-adapter", -- As I'm using mason, this will be in the path
                    args = {"${port}"},
                }
            }

            dap.adapters['chrome'] = {
                type = 'executable',
                command = 'node',
                args = {os.getenv('HOME') .. '/.local/share/nvim/mason/packages/chrome-debug-adapter/out/src/chromeDebug.js'}
            }

            for _, language in ipairs { 'typescript', 'javascript', 'typescriptreact', 'javascriptreact' } do
                dap.configurations[language] = {
                    {
                        type = 'pwa-node',
                        request = 'launch',
                        name = 'Launch File',
                        program = "${file}",
                        cmd = "${workspaceFolder}",
                        -- runtimeExecutable = 'node',
                        -- sourceMaps = true,
                    },
                    {
                        name = "Attach node debugger by process",
                        type = "pwa-node",
                        request = "attach",
                        processId = require("dap.utils").pick_process,
                        cwd = "${workspaceFolder}",
                        -- sourceMaps = true,
                    },
                    {
                        name = "Attach node debugger by port",
                        type = "pwa-node",
                        request = "attach",
                        port = 9229,
                        cwd = "${workspaceFolder}",
                        -- sourceMaps = true,
                    },
                    {
                        name = "Attach Chrome Debugger",
                        type = "chrome",
                        request = "attach",
                        sourceMaps = true,
                        cwd = vim.fn.getcwd(),
                        protocol = "inspector",
                        webRoot = "${workspaceFolder}",
                        port = 9229,
                    }
                }
            end

            -- C++
            -- This configuration is project specific. The next step is to get 
            -- launch configs working so we can store these in the project.
            dap.configurations.cpp = {
                {
                    name = "launch debug mediaserver",
                    type = "codelldb",
                    request = "launch",
                    program = "${workspaceFolder}/build-macos-11.1-arm64/bin/sdna-mediaserver",
                },
            }

            dap.adapters['codelldb'] = {
                type = "server",
                port = "${port}",
                executable = {
                    command = os.getenv('HOME') .. "/.local/share/nvim/mason/bin/codelldb",
                    args = { "--port", "${port}" },
                },
            }
        end
    },
    {
        'theHamsta/nvim-dap-virtual-text',
        config = function ()
            require("nvim-dap-virtual-text").setup()
        end
    },
}
