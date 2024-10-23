return {
    'rcarriga/nvim-notify',
    config = function ()
        vim.opt.termguicolors = true

        vim.notify = require('notify')

        vim.notify.setup({
            background_colour = "#000000",
        })
    end
}
