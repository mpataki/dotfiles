-- full config: https://github.com/obsidian-nvim/obsidian.nvim?tab=readme-ov-file#configuration-options
return {
  "obsidian-nvim/obsidian.nvim",
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
  config = function ()
      require('obsidian').setup({
          -- Use new callbacks API instead of deprecated mappings
          callbacks = {
              enter_note = function(note)
                  -- Keep gf for following links
                  vim.keymap.set("n", "gf", function()
                      return require("obsidian").util.gf_passthrough()
                  end, { noremap = false, expr = true, buffer = true })
              end,
          },

          -- Disable legacy commands (use new command names)
          legacy_commands = false,

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
              folder = "03-resources/dailies",
              -- Optional, if you want to change the date format for the ID of daily notes.
              date_format = "%Y/%m/%Y-%m-%d-daily",
              -- Optional, if you want to change the date format of the default alias of daily notes.
              alias_format = "%B %-d, %Y",
              -- Optional, default tags to add to each new daily note created.
              default_tags = { "daily-notes" },
              -- Optional, if you want to automatically insert a template from your template directory like 'daily.md'
              template = "daily-note-template.md"
          },

          templates = {
              folder = "templates",
              date_format = "%Y-%m-%d",
              time_format = "%H:%M",
              substitutions = {}
          },

          -- Checkbox configuration (replaces ui.checkboxes)
          checkbox = {
              order = { " ", "x", "~", "!", ">" },
          },

          -- Selective UI features for Obsidian-specific syntax
          ui = {
              enable = true,
              update_debounce = 200,
              -- Disable bullets (handled by render-markdown.nvim)
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

          -- Note: follow_url_func is deprecated. The plugin now uses vim.ui.open by default.
          -- See https://github.com/obsidian-nvim/obsidian.nvim/wiki/Attachment for details.
      })

      vim.keymap.set('n', '<leader>on', ':Obsidian new<CR>', { })
      vim.keymap.set('n', '<leader>ot', ':Obsidian tags<CR>', { })
      vim.keymap.set('n', '<leader>ol', ':Obsidian links<CR>', { silent = true })
      vim.keymap.set('v', '<leader>of', ':Obsidian link_new<CR>', { })
      vim.keymap.set('n', '<leader>os', ':Obsidian search<CR>', { noremap = true, silent = true })
      vim.keymap.set('n', '<leader>oj', ':Obsidian today<CR>', { silent = true })
      vim.keymap.set('n', '<leader>ok', ':Obsidian tomorrow<CR>', { silent = true })
      vim.keymap.set('n', '<leader>oh', ':Obsidian yesterday<CR>', { silent = true })
      vim.keymap.set('n', '<leader>or', ':Obsidian rename<CR>', { silent = true })
      vim.keymap.set('n', '<leader>oc', ':Obsidian toggle_checkbox<CR>', { expr = true, silent = true })
      vim.keymap.set('n', '<leader>od', ':Obsidian dailies<CR>', { silent = true })
      -- Reload obsidian.nvim to pick up externally created files
      vim.keymap.set('n', '<leader>oR', ':Lazy reload obsidian.nvim<CR>', { silent = true })

      -- Create an autocommand group for Obsidian auto-commit
      local obsidian_autocommit = vim.api.nvim_create_augroup('ObsidianAutoCommit', { clear = true })

      -- Auto-check for file changes when focusing Neovim in vault
      vim.api.nvim_create_autocmd({'FocusGained', 'BufEnter'}, {
          pattern = vim.fn.expand("~") .. "/obsidian-notes-vault/**/*.md",
          callback = function()
              vim.cmd('checktime')  -- Check if files have changed on disk
          end,
      })

      -- Create the autocommand for auto-committing on save
  --     vim.api.nvim_create_autocmd('BufWritePost', {
  --         group = obsidian_autocommit,
  --         pattern = vim.fn.expand("~") .. "/obsidian-notes-vault/**",
  --         callback = function()
  --             local file = vim.fn.expand('%:p')
  --             local vault_path = vim.fn.expand("~") .. "/obsidian-notes-vault"
  --
  --             -- Get the relative path for the commit message
  --             local relative_path = string.sub(file, #vault_path + 2)
  --
  --             -- Run git commands
  --             vim.fn.system(string.format('cd %s && git add "%s" && git commit -m "Auto-commit: %s" && git push',
  --             vault_path,
  --             relative_path,
  --             relative_path
  --             ))
  --         end,
  --     })
  end
}
