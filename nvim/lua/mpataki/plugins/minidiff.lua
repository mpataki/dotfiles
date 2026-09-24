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
                goto_first = '[H',
                goto_prev = '[h',
                goto_next = ']h',
                goto_last = ']H',
                textobject = 'ih',
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

        -- PR review mode: diff against the PR's merge-base instead of HEAD.
        -- Identity (base sha, repo root) comes from mpataki.review.pr so the
        -- path handed to `git show` is repo-relative regardless of nvim's cwd.
        local pr = require('mpataki.review.pr')
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
          local root = pr.root(path)
          if not root then return end

          local rel = pr.relpath(root, path)
          if not rel then return end

          local r = pr.git(root, { 'show', pr_base_ref .. ':' .. rel })
          if r.code ~= 0 then
            -- File didn't exist at base — use empty ref so all lines show as added
            diff.set_ref_text(bufnr, {})
          else
            diff.set_ref_text(bufnr, r.stdout)
          end
          pr_ref_applied[bufnr] = true
        end

        vim.api.nvim_create_user_command('DiffPRBase', function(opts)
          local root = pr.current_root()
          if not root then
            vim.notify('DiffPRBase: not in a git repo', vim.log.levels.ERROR)
            return
          end

          local base
          if opts.args ~= '' then
            local r = pr.git(root, { 'rev-parse', opts.args })
            if r.code ~= 0 then
              vim.notify('Could not resolve ref: ' .. opts.args, vim.log.levels.ERROR)
              return
            end
            base = vim.trim(r.stdout)
          else
            -- refresh: an explicit gesture re-resolves the base, so a session
            -- does not freeze on a merge-base the branch has since moved past.
            local info, err = pr.info(root, { refresh = true })
            if not info then
              vim.notify('DiffPRBase: ' .. err, vim.log.levels.ERROR)
              return
            end
            base = info.base_sha
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

          vim.notify('mini.diff: reviewing against ' .. base:sub(1, 8), vim.log.levels.INFO)
        end, { desc = 'Set mini.diff reference (defaults to PR merge-base)', nargs = '?' })

        vim.api.nvim_create_user_command('DiffReset', function()
          pr_base_ref = nil
          pr_ref_applied = {}
          pr.clear_cache()

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
