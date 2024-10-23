return {
    'f-person/git-blame.nvim',
    config = function()
        require('gitblame').setup({
            enabled = false, -- off until toggled on
        })
    end,
}
