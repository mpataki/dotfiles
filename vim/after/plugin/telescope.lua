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
telescope.load_extension('dap')

vim.keymap.set('n', '<leader>pf', builtin.find_files, {})
vim.keymap.set('n', '<C-p>', builtin.git_files, {})
vim.keymap.set('n', '<leader>ps', function()
	builtin.grep_string({ search = vim.fn.input("Grep > ") });
end)

