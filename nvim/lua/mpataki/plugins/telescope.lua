return {
    'nvim-telescope/telescope.nvim',
    dependencies = {
        { 'nvim-lua/plenary.nvim' },
        { 'nvim-telescope/telescope-ui-select.nvim' },
        { 'nvim-telescope/telescope-fzf-native.nvim', build = 'make' },
    },
    cmd = 'TSUpdate',
    config = function()
        local telescope = require('telescope')
        local actions = require("telescope.actions")
        local builtin = require('telescope.builtin')

        telescope.setup({
            defaults = {
                layout_strategy = 'vertical',
                layout_config = {
                    vertical = {
                        preview_cutoff = 10,
                        preview_height = 0.5,
                        width = 0.95,
                        height = 0.95,
                    },
                },
                mappings = {
                    i = {
                        ["<esc>"] = actions.close
                    }
                },
            },
            pickers = {
                find_files = {
                    path_display = {"smart"},
                    layout_strategy = "vertical",
                },
                buffers = {
                    path_display = {"smart"},
                    layout_strategy = "vertical",
                },
                live_grep = {
                    path_display = {"smart"},
                    layout_strategy = "vertical",
                },
            },
            extensions = {
                ['ui-select'] = {
                    require('telescope.themes').get_dropdown({})
                }
            }
        })

        telescope.load_extension("ui-select")
        telescope.load_extension("fzf")

        -- vim.keymap.set('n', '<leader>pf', builtin.find_files, {})
        -- vim.keymap.set('n', '<C-p>', builtin.git_files, {})
        vim.keymap.set('n', '<C-p>', builtin.find_files, {})
        -- vim.keymap.set('n', '<leader>ps', function()
        --     builtin.grep_string({ search = vim.fn.input("Grep > ") });
        -- end)

        vim.keymap.set('n', '<leader>b', function()
            builtin.buffers();
        end)

        vim.keymap.set('n', '<leader>ps', builtin.live_grep, {})
        vim.keymap.set('n', '<leader>pw', builtin.grep_string, {})
        vim.keymap.set('n', '<leader>pc', builtin.commands, {})
        vim.keymap.set('n', '<leader>pk', builtin.keymaps, {})
        vim.keymap.set('n', '<leader>ph', builtin.help_tags, {})
        vim.keymap.set('n', '<leader>po', builtin.oldfiles, {})
        vim.keymap.set('n', '<leader>pr', builtin.resume, {})
        vim.keymap.set('n', '<leader>pd', builtin.lsp_document_symbols, {})
        vim.keymap.set('n', '<leader>pS', builtin.lsp_workspace_symbols, {})
    end
}
