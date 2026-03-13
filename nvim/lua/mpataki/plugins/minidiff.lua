return {
    'echasnovski/mini.diff',
    version = false,
    config = function()
        local diff = require('mini.diff')

        diff.setup({
            view = {
                style = 'sign',  -- Show signs in sign column by default
            },

            mappings = {
                apply = '<leader>ga',
                reset = '<leader>gr',
                goto_first = '[C',
                goto_prev = '[c',
                goto_next = ']c',
                goto_last = ']C',
                textobject = 'ic',   -- "Inner Hunk" text object
            },

            -- Delays (in ms) defining asynchronous processes
            delay = {
                -- How much to wait before update following every text change
                text_change = 200,
            },
        })

        vim.keymap.set('n', '<leader>go', function()
            diff.toggle_overlay()
        end, { desc = 'Toggle inline diff overlay' })

        -- PR review mode: diff against merge-base instead of HEAD
        local pr_review_group = nil
        local pr_base_ref = nil
        local pr_ref_applied = {} -- track which buffers already have the PR ref

        local function set_pr_ref_for_buf(bufnr)
          if not pr_base_ref then return end
          if not vim.api.nvim_buf_is_valid(bufnr) then return end
          if pr_ref_applied[bufnr] then return end

          -- Skip buffers that mini.diff hasn't enabled (diffview panels, special buffers, etc.)
          local buf_data = diff.get_buf_data(bufnr)
          if not buf_data then return end

          local path = vim.api.nvim_buf_get_name(bufnr)
          if path == '' then return end

          local rel = vim.fn.fnamemodify(path, ':.')
          local content = vim.fn.system({ 'git', 'show', pr_base_ref .. ':' .. rel })
          if vim.v.shell_error ~= 0 then
            -- File didn't exist at base — use empty ref so all lines show as added
            diff.set_ref_text(bufnr, {})
          else
            diff.set_ref_text(bufnr, content)
          end
          pr_ref_applied[bufnr] = true
        end

        vim.api.nvim_create_user_command('DiffPRBase', function()
          local base = vim.fn.system("git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null"):gsub("%s+", "")
          if base == "" then
            vim.notify("Could not find merge base", vim.log.levels.ERROR)
            return
          end

          pr_base_ref = base
          pr_ref_applied = {}

          -- Apply to current buffer
          set_pr_ref_for_buf(vim.api.nvim_get_current_buf())

          -- Auto-apply after mini.diff attaches and sets initial ref text
          pr_review_group = vim.api.nvim_create_augroup('MiniDiffPRReview', { clear = true })
          vim.api.nvim_create_autocmd('User', {
            group = pr_review_group,
            pattern = 'MiniDiffUpdated',
            callback = function() set_pr_ref_for_buf(vim.api.nvim_get_current_buf()) end,
          })

          vim.notify("mini.diff: reviewing against " .. base:sub(1, 8), vim.log.levels.INFO)
        end, { desc = "Set mini.diff reference to PR merge-base" })

        vim.api.nvim_create_user_command('DiffReset', function()
          pr_base_ref = nil
          pr_ref_applied = {}

          if pr_review_group then
            vim.api.nvim_del_augroup_by_id(pr_review_group)
            pr_review_group = nil
          end

          -- Re-enable default git source for current buffer
          local bufnr = vim.api.nvim_get_current_buf()
          diff.disable(bufnr)
          diff.enable(bufnr)

          vim.notify("mini.diff: restored to default (HEAD)", vim.log.levels.INFO)
        end, { desc = "Restore mini.diff to default HEAD reference" })
    end
}
