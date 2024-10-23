-- full config: https://github.com/epwalsh/obsidian.nvim?tab=readme-ov-file#configuration-options
return {
  "epwalsh/obsidian.nvim",
  version = "*",  -- recommended, use latest release instead of latest commit
  -- Replace the below lines with this if you only want to load obsidian.nvim for markdown files in your vault:
  -- event = {
  --   -- If you want to use the home shortcut '~' here you need to call 'vim.fn.expand'.
  --   -- E.g. "BufReadPre " .. vim.fn.expand "~" .. "/my-vault/*.md"
  --   -- refer to `:h file-pattern` for more examples
  --   "BufReadPre " .. vim.fn.expand("~") .. "/obsidian-notes-vault/*.md",
  --   "BufNewFile " .. vim.fn.expand("~") .. "/obsidian-notes-vault/*.md",
  -- },
  dependencies = {
    -- Required.
    "nvim-lua/plenary.nvim",

    -- see below for full list of optional dependencies 👇
  },
  opts = {
    workspaces = {
      {
        name = "personal",
        path = vim.fn.expand("~") .. "/obsidian-notes-vault",
      },
    },
  },
  -- mappings = {},
--   config = function ()
--       vim.keymap.set('n', '<leader>os', '<cmd>:ObsidianSearch<CR>')
--   end
}
