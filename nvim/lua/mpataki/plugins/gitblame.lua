return {
    'f-person/git-blame.nvim',
    config = function()
        require('gitblame').setup({
            enabled = false, -- off until toggled on
        })

        vim.keymap.set('n', '<Leader>gb', ':GitBlameToggle<CR>', { desc = 'Toggle git blame' })
        vim.keymap.set('n', '<Leader>gl', ':GitBlameCopyFileURL<CR>', { desc = 'Copy git blame link' })
    end,
}
