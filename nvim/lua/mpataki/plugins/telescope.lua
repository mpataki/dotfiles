return {
    'nvim-telescope/telescope.nvim',
    dependencies = {
        { 'nvim-lua/plenary.nvim' },
        { 'nvim-telescope/telescope-ui-select.nvim' },
    },
    cmd = 'TSUpdate',
    config = function()
        local telescope = require('telescope')
        local actions = require("telescope.actions")
        local builtin = require('telescope.builtin')

        telescope.setup({
            defaults = {
                mappings = {
                    i = {
                        ["<esc>"] = actions.close
                    }
                },
            },
            extensions = {
                ['ui-select'] = {
                    require('telescope.themes').get_dropdown({
                    })
                }
            }
        })

        telescope.load_extension("ui-select")

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
    end
}
