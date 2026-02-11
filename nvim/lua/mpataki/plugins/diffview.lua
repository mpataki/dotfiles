return {
  'sindrets/diffview.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim',
  },
  config = function()
    local diffview = require('diffview')

    diffview.setup({
      view = {
        default = {
          layout = "diff2_horizontal",
          winbar_info = true,
        },
        merge_tool = {
          layout = "diff3_horizontal",
        },
      },
    })

    -- Set up keymaps
    vim.keymap.set('n', '<leader>gd', '<cmd>DiffviewOpen<CR>', { noremap = true, silent = true, desc = "Open Diffview" })
    vim.keymap.set('n', '<leader>gf', '<cmd>DiffviewToggleFiles<CR>', { noremap = true, silent = true, desc = "Toggle Diffview file panel" })
  end
}
