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
  },
  -- mappings = {},
  config = function ()
      require('obsidian').setup({
          workspaces = {
              {
                  name = "personal",
                  path = vim.fn.expand("~") .. "/obsidian-notes-vault",
              },
          },
          daily_notes = {
              -- Optional, if you keep daily notes in a separate directory.
              folder = "dailies",
              -- Optional, if you want to change the date format for the ID of daily notes.
              date_format = "%Y-%m-%d",
              -- Optional, if you want to change the date format of the default alias of daily notes.
              alias_format = "%B %-d, %Y",
              -- Optional, default tags to add to each new daily note created.
              default_tags = { "daily-notes" },
              -- Optional, if you want to automatically insert a template from your template directory like 'daily.md'
              template = nil
          },
      })

      -- gd passthrough
      vim.keymap.set("n", "gd", function()
          if require("obsidian").util.cursor_on_markdown_link() then
              return "<cmd>ObsidianFollowLink<CR>"
          else
              return "gd"
          end
      end, { noremap = false, expr = true })

      vim.keymap.set('n', '<leader>os', ':ObsidianSearch<CR>', { noremap = true, silent = true })
      vim.keymap.set('n', '<leader>oj', ':ObsidianToday<CR>', { silent = true })
      vim.keymap.set('n', '<leader>ol', ':ObsidianTomorrow<CR>', { silent = true })
      vim.keymap.set('n', '<leader>oh', ':ObsidianYesterday<CR>', { silent = true })
      vim.keymap.set('n', '<leader>or', ':ObsidianRename<CR>', { silent = true })
      vim.keymap.set('n', '<leader>ot', ':ObsidianToggleCheckbox<CR>', { expr = true, silent = true })
      vim.keymap.set('n', '<leader>od', ':ObsidianDailies<CR>', { silent = true })

      -- Create an autocommand group for Obsidian auto-commit
      local obsidian_autocommit = vim.api.nvim_create_augroup('ObsidianAutoCommit', { clear = true })

      -- Create the autocommand for auto-committing on save
      vim.api.nvim_create_autocmd('BufWritePost', {
          group = obsidian_autocommit,
          pattern = vim.fn.expand("~") .. "/obsidian-notes-vault/**",
          callback = function()
              local file = vim.fn.expand('%:p')
              local vault_path = vim.fn.expand("~") .. "/obsidian-notes-vault"

              -- Get the relative path for the commit message
              local relative_path = string.sub(file, #vault_path + 2)

              -- Run git commands
              vim.fn.system(string.format('cd %s && git add "%s" && git commit -m "Auto-commit: %s" && git push', 
              vault_path,
              relative_path,
              relative_path
              ))
          end,
      })
  end
}
