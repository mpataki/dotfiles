
require("neo-tree").setup({
    filesystem = {
        hijack_netrw_behavior = "open_current"
    }
})

vim.keymap.set('n', '<Leader>t', '<cmd>:Neotree position=current<CR>')

