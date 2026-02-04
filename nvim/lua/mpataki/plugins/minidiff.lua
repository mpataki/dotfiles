return {
    'echasnovski/mini.diff',
    version = false,
    config = function()
        local diff = require('mini.diff')

        diff.setup({
            view = {
                style = 'sign',  -- Show signs in sign column by default
            },

            mappings = {
                apply = '<leader>ca',
                reset = '<leader>cr',
                goto_first = '[C',
                goto_prev = '[c',
                goto_next = ']c',
                goto_last = ']C',
                textobject = 'ic',   -- "Inner Hunk" text object
            },

            -- Delays (in ms) defining asynchronous processes
            delay = {
                -- How much to wait before update following every text change
                text_change = 200,
            },
        })

        vim.keymap.set('n', '<leader>cv', function()
            diff.toggle_overlay()
        end, { desc = 'Toggle inline diff' })
    end
}
