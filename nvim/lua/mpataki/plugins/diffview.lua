return {
  'sindrets/diffview.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim',
  },
  config = function()
    local diffview = require('diffview')

    diffview.setup({
      -- Default configuration
    })

    -- Set up keymaps
    vim.keymap.set('n', '<leader>d', '<cmd>DiffviewOpen<CR>', { noremap = true, silent = true, desc = "Open Diffview" })
  end
}
