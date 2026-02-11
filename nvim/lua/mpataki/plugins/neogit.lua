return {
  "NeogitOrg/neogit",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "sindrets/diffview.nvim",
    "nvim-telescope/telescope.nvim",
  },
  lazy = false,
  priority = 1,
  config = function ()
      local neogit = require("neogit")

      neogit.setup {
          graph_style = "unicode",
      }

      vim.keymap.set('n', '<leader>gs', function() neogit.open() end, { desc = 'Neogit status' })
  end
}
