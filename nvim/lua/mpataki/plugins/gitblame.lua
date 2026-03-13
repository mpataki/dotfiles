return {
    'f-person/git-blame.nvim',
    config = function()
        require('gitblame').setup({
            enabled = false, -- off until toggled on
        })

        vim.keymap.set('n', '<Leader>gb', ':GitBlameToggle<CR>', { desc = 'Toggle git blame' })
    end,
}
