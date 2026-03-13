return {
  'sindrets/diffview.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim',
  },
  config = function()
    local diffview = require('diffview')

    local function goto_main_tab()
      local lib = require('diffview.lib')
      local view = lib.get_current_view()
      if not view then
        vim.notify("Not in a Diffview", vim.log.levels.WARN)
        return
      end

      local line = vim.fn.line('.')
      local col = vim.fn.col('.')
      local file = view:infer_cur_file()
      if not file or not file.absolute_path then
        vim.notify("Could not resolve file path", vim.log.levels.WARN)
        return
      end

      vim.cmd('1tabnext')
      vim.cmd('edit ' .. vim.fn.fnameescape(file.absolute_path))
      vim.api.nvim_win_set_cursor(0, { line, col - 1 })
      vim.cmd('normal! zz')
    end

    diffview.setup({
      view = {
        default = {
          layout = "diff2_horizontal",
          winbar_info = true,
        },
        merge_tool = {
          layout = "diff3_horizontal",
        },
      },
      keymaps = {
        view = {
          { "n", "<leader>ge", goto_main_tab, { desc = "Jump to file+line in main tab" } },
        },
      },
    })

    vim.api.nvim_create_user_command('DiffviewPR', function()
      local base = vim.fn.system("git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null"):gsub("%s+", "")
      if base == "" then
        vim.notify("Could not find merge base", vim.log.levels.ERROR)
        return
      end
      vim.cmd("DiffviewOpen " .. base .. "...HEAD")
      vim.cmd("DiffPRBase")
    end, { desc = "Open Diffview against base branch (PR diff)" })

    -- Set up keymaps
    vim.keymap.set('n', '<leader>gd', '<cmd>DiffviewOpen<CR>', { noremap = true, silent = true, desc = "Open Diffview" })
    vim.keymap.set('n', '<leader>gf', '<cmd>DiffviewToggleFiles<CR>', { noremap = true, silent = true, desc = "Toggle Diffview file panel" })
    vim.keymap.set('n', '<leader>gp', '<cmd>DiffviewPR<CR>', { noremap = true, silent = true, desc = "Diffview against base branch (PR diff)" })
  end
}
