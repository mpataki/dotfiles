return {
  "folke/which-key.nvim",
  event = "VeryLazy",
  opts = {
    preset = "modern",
    delay = 500,
    spec = {
      { "<leader>r", group = "Requests (kulala)" },
      { "<leader>g", group = "Git" },
      { "<leader>f", group = "Find" },
      { "<leader>s", group = "Spelunk / split" },
    },
  },
  keys = {
    {
      "<leader>?",
      function()
        require("which-key").show({ global = false })
      end,
      desc = "Buffer-local keymaps",
    },
  },
}
