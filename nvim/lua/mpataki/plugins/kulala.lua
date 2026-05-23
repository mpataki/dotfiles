return {
  {
    "mistweaverco/kulala.nvim",
    -- Pinned to v5.x — v6.0.0 introduced the kulala-core architecture
    -- and broke variable handling / shared-flow state. Revisit when v6.x
    -- stabilises.
    version = "5.x",
    keys = {
      { "<leader>rs", desc = "Send request" },
      { "<leader>ra", desc = "Send all requests" },
      { "<leader>rb", desc = "Open scratchpad" },
    },
    ft = { "http", "rest" },
    opts = {
      global_keymaps = true,
      global_keymaps_prefix = "<leader>r",
      kulala_keymaps_prefix = "",
    },
    config = function(_, opts)
      require("kulala").setup(opts)
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "http", "rest" },
        callback = function()
          vim.keymap.set({ "n", "v" }, "<leader>e", function()
            require("kulala").run()
          end, { buffer = true, desc = "Send request" })
        end,
      })
    end,
  },
}
