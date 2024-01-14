return {
    { 'rcarriga/nvim-dap-ui' },
    { 'jay-babu/mason-nvim-dap.nvim' },
    {
        'mfussenegger/nvim-dap',
        dependenvies = {
        },
        config = function()
            require('dapui').setup()

            vim.fn.sign_define('DapBreakpoint', {text='•', texthl='red', linehl='', numhl=''})

            vim.keymap.set('n', '<F5>', function() require('dap').continue() end)
            vim.keymap.set('n', '<F10>', function() require('dap').step_over() end)
            vim.keymap.set('n', '<F11>', function() require('dap').step_into() end)
            vim.keymap.set('n', '<F12>', function() require('dap').step_out() end)
            vim.keymap.set('n', '<Leader>b', function() require('dap').toggle_breakpoint() end)
            vim.keymap.set('n', '<Leader>B', function() require('dap').set_breakpoint() end)
            vim.keymap.set('n', '<Leader>lp', function() require('dap').set_breakpoint(nil, nil, vim.fn.input('Log point message: ')) end)
            vim.keymap.set('n', '<Leader>dr', function() require('dap').repl.open() end)
            vim.keymap.set('n', '<Leader>dl', function() require('dap').run_last() end)

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

            vim.keymap.set('n', '<Leader>dc', function()
                require('dap').repl.open()
            end)

            vim.keymap.set({'n', 'v'}, '<Leader>du', function()
                require('jdtls.dap').setup_dap_main_class_configs()
                require('dap.ext.vscode').load_launchjs('./launch.json')
                require("dapui").toggle()
            end)
        end
    }
}
