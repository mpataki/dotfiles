-- full config: https://github.com/obsidian-nvim/obsidian.nvim?tab=readme-ov-file#configuration-options
return {
  "obsidian-nvim/obsidian.nvim",
  version = "*",  -- recommended, use latest release instead of latest commit
  event = {
    "BufReadPre " .. vim.fn.expand("~") .. "/obsidian-notes-vault/*.md",
    "BufNewFile " .. vim.fn.expand("~") .. "/obsidian-notes-vault/*.md",
  },
  -- Also load on the :Obsidian command or any <leader>o* key, so the plugin
  -- is reachable from buffers outside the vault (which is the whole point of
  -- shortcuts like <leader>oj "today" and <leader>os "search").
  cmd = { "Obsidian" },
  keys = {
    { "<leader>on", "<cmd>Obsidian new<cr>",              desc = "Obsidian: new note" },
    { "<leader>ot", "<cmd>Obsidian tags<cr>",             desc = "Obsidian: tags" },
    { "<leader>ol", "<cmd>Obsidian links<cr>",            desc = "Obsidian: links",            silent = true },
    { "<leader>of", "<cmd>Obsidian link_new<cr>",         desc = "Obsidian: link selection",   mode = "v" },
    { "<leader>os", "<cmd>Obsidian search<cr>",           desc = "Obsidian: search",           silent = true },
    { "<leader>oj", "<cmd>Obsidian today<cr>",            desc = "Obsidian: today",            silent = true },
    { "<leader>ok", "<cmd>Obsidian tomorrow<cr>",         desc = "Obsidian: tomorrow",         silent = true },
    { "<leader>oh", "<cmd>Obsidian yesterday<cr>",        desc = "Obsidian: yesterday",        silent = true },
    { "<leader>or", "<cmd>Obsidian rename<cr>",           desc = "Obsidian: rename",           silent = true },
    { "<leader>oc", "<cmd>Obsidian toggle_checkbox<cr>",  desc = "Obsidian: toggle checkbox",  silent = true },
    { "<leader>od", "<cmd>Obsidian dailies<cr>",          desc = "Obsidian: dailies",          silent = true },
    { "<leader>oR", "<cmd>Lazy reload obsidian.nvim<cr>", desc = "Obsidian: reload plugin",    silent = true },
  },
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

          -- Disable obsidian UI entirely; render-markdown.nvim handles rendering
          ui = { enable = false },

          -- Note: follow_url_func is deprecated. The plugin now uses vim.ui.open by default.
          -- See https://github.com/obsidian-nvim/obsidian.nvim/wiki/Attachment for details.
      })

      -- Keymaps live in the lazy spec's `keys = { … }` table above so they
      -- exist from startup and trigger plugin load on first press.

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
