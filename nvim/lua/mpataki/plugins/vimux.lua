return {
    "preservim/vimux",
    init = function()
        vim.g.VimuxOrientation = "h"
        vim.g.VimuxHeight = "38%"
        vim.g.VimuxOpenExtraArgs = "-b" -- for "before", referring to the new pane position relative to the current one (so, on the left)

        vim.keymap.set('n', '<leader>tp', ':VimuxPromptCommand<CR>', { noremap = true, silent = true })
        vim.keymap.set('n', '<leader>tl', ':VimuxRunLastCommand<CR>', { noremap = true, silent = true })
        vim.keymap.set('n', '<leader>tq', ':VimuxCloseRunner<CR>', { noremap = true, silent = true })
        vim.keymap.set('n', '<leader>tx', ':VimuxInterruptRunner<CR>', { noremap = true, silent = true })
        vim.keymap.set('n', '<leader>tz', ':VimuxZoomRunner<CR>', { noremap = true, silent = true })
        vim.keymap.set('n', '<leader>tk', ':VimuxClearTerminalScreen<CR>', { noremap = true, silent = true })
    end
}
