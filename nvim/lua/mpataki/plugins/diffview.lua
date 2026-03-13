return {
  'sindrets/diffview.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim',
  },
  config = function()
    local diffview = require('diffview')

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
    })

    vim.api.nvim_create_user_command('DiffviewPR', function()
      local base = vim.fn.system("git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null"):gsub("%s+", "")
      if base == "" then
        vim.notify("Could not find merge base", vim.log.levels.ERROR)
        return
      end
      vim.cmd("DiffviewOpen " .. base .. "...HEAD")
    end, { desc = "Open Diffview against base branch (PR diff)" })

    -- Set up keymaps
    vim.keymap.set('n', '<leader>gd', '<cmd>DiffviewOpen<CR>', { noremap = true, silent = true, desc = "Open Diffview" })
    vim.keymap.set('n', '<leader>gf', '<cmd>DiffviewToggleFiles<CR>', { noremap = true, silent = true, desc = "Toggle Diffview file panel" })
    vim.keymap.set('n', '<leader>gp', '<cmd>DiffviewPR<CR>', { noremap = true, silent = true, desc = "Diffview against base branch (PR diff)" })
  end
}
