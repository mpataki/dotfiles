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
          layout = "diff2_vertical",
          winbar_info = true,
        },
        merge_tool = {
          layout = "diff3_vertical",
        },
      },
    })

    -- Set up keymaps
    vim.keymap.set('n', '<leader>d', '<cmd>DiffviewOpen<CR>', { noremap = true, silent = true, desc = "Open Diffview" })
  end
}
