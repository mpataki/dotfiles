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

          -- Optional, if you keep notes in a specific subdirectory of your vault.
          notes_subdir = "inbox",

          -- Where to put new notes. Valid options are
          --  * "current_dir" - put new notes in same directory as the current buffer.
          --  * "notes_subdir" - put new notes in the default notes subdirectory.
          new_notes_location = "notes_subdir",

          daily_notes = {
              -- Optional, if you keep daily notes in a separate directory.
              folder = "resources/dailies",
              -- Optional, if you want to change the date format for the ID of daily notes.
              date_format = "%Y-%m-%d",
              -- Optional, if you want to change the date format of the default alias of daily notes.
              alias_format = "%B %-d, %Y",
              -- Optional, default tags to add to each new daily note created.
              default_tags = { "daily-notes" },
              -- Optional, if you want to automatically insert a template from your template directory like 'daily.md'
              template = nil
          },

          -- Selective UI features for Obsidian-specific syntax
          ui = {
              enable = true,
              update_debounce = 200,
              -- Disable checkboxes and bullets (handled by render-markdown.nvim)
              checkboxes = {},
              bullets = {},
              -- Enable only Obsidian-specific features
              external_link_icon = { char = "", hl_group = "ObsidianExtLinkIcon" },
              reference_text = { hl_group = "ObsidianRefText" },
              highlight_text = { hl_group = "ObsidianHighlightText" },
              tags = { hl_group = "ObsidianTag" },
              block_ids = { hl_group = "ObsidianBlockID" },
              hl_groups = {
                  ObsidianTag = { fg = "#89ddff", italic = true },
                  ObsidianRefText = { underline = true },
                  ObsidianHighlightText = { bg = "#75662e" },
                  ObsidianBlockID = { fg = "#89ddff", italic = true },
                  ObsidianExtLinkIcon = { fg = "#c792ea" },
              },
          },

          -- Optional, by default when you use `:ObsidianFollowLink` on a link to an external
          -- URL it will be ignored but you can customize this behavior here.
          ---@param url string
          follow_url_func = function(url)
              -- Open the URL in the default web browser.
              vim.fn.jobstart({"open", url})  -- Mac OS
              -- vim.fn.jobstart({"xdg-open", url})  -- linux
              -- vim.cmd(':silent exec "!start ' .. url .. '"') -- Windows
              -- vim.ui.open(url) -- need Neovim 0.10.0+
          end,
      })

      vim.keymap.set('n', '<leader>on', ':ObsidianNew<CR>', { })
      vim.keymap.set('n', '<leader>ot', ':ObsidianTags<CR>', { })
      vim.keymap.set('n', '<leader>ol', ':ObsidianLinks<CR>', { silent = true })
      vim.keymap.set('v', '<leader>of', ':ObsidianLinkNew<CR>', { })
      vim.keymap.set('n', '<leader>os', ':ObsidianSearch<CR>', { noremap = true, silent = true })
      vim.keymap.set('n', '<leader>oj', ':ObsidianToday<CR>', { silent = true })
      vim.keymap.set('n', '<leader>ok', ':ObsidianTomorrow<CR>', { silent = true })
      vim.keymap.set('n', '<leader>oh', ':ObsidianYesterday<CR>', { silent = true })
      vim.keymap.set('n', '<leader>or', ':ObsidianRename<CR>', { silent = true })
      vim.keymap.set('n', '<leader>oc', ':ObsidianToggleCheckbox<CR>', { expr = true, silent = true })
      vim.keymap.set('n', '<leader>od', ':ObsidianDailies<CR>', { silent = true })
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
