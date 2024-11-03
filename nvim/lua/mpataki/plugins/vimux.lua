return {
    "preservim/vimux",
    init = function()
        vim.g.VimuxOrientation = "h"
        vim.g.VimuxHeight = "38%"

        vim.keymap.set('n', '<leader>vp', ':VimuxPromptCommand<CR>', { noremap = true, silent = true })
        vim.keymap.set('n', '<leader>vl', ':VimuxRunLastCommand<CR>', { noremap = true, silent = true })
        vim.keymap.set('n', '<leader>vq', ':VimuxCloseRunner<CR>', { noremap = true, silent = true })
        vim.keymap.set('n', '<leader>vx', ':VimuxInterruptRunner<CR>', { noremap = true, silent = true })
        vim.keymap.set('n', '<leader>vz', ':VimuxZoomRunner<CR>', { noremap = true, silent = true })
        vim.keymap.set('n', '<leader>vk', ':VimuxClearTerminalScreen<CR>', { noremap = true, silent = true })
    end
}
