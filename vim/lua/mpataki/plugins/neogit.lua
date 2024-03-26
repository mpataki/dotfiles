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
      print("loading neogit")
      local neogit = require("neogit")

      neogit.setup {
          graph_style = "unicode",
      }
  end
}
