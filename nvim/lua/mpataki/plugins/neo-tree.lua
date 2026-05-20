return {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-tree/nvim-web-devicons",
        "MunifTanjim/nui.nvim",
        -- "3rd/image.nvim", -- Optional image support in preview window: See `# Preview Mode` for more information
    },
    config = function()
        require("neo-tree").setup({
            filesystem = {
                hijack_netrw_behavior = "open_current",
                use_libuv_file_watcher = true,
                follow_current_file = {
                    enabled = true,
                    leave_dirs_open = true,
                },
                filtered_items = {
                    always_show = {
                        ".github"
                    },
                }
            },
            window = {
                width = 50,
            },
            default_component_configs = {
                created = { enabled = false },
                last_modified = { enabled = false },
                file_size = { enabled = false },
                type = { enabled = false },
            }
        })

        -- vim.keymap.set('n', '<Leader>t', '<cmd>:Neotree position=current<CR>')
        vim.keymap.set('n', '<Leader>ls', ':Neotree<CR>', { desc = 'Neotree' })

        local pr_tree_active = false
        vim.keymap.set('n', '<leader>gt', function()
            vim.cmd('Neotree git_base=HEAD')
            if pr_tree_active then
                vim.cmd('DiffReset')
                pr_tree_active = false
            end
        end, { desc = 'Neotree (HEAD)' })
        vim.keymap.set('n', '<leader>gT', function()
            local base_branch
            local base = vim.fn.system("git merge-base HEAD main 2>/dev/null"):gsub("%s+", "")
            if base ~= "" then
                base_branch = 'main'
            else
                base = vim.fn.system("git merge-base HEAD master 2>/dev/null"):gsub("%s+", "")
                base_branch = 'master'
            end
            if base == "" then
                vim.notify("Could not find merge base", vim.log.levels.ERROR)
                return
            end
            vim.cmd('Neotree git_base=' .. base)
            print('PR diff vs ' .. base_branch)
            pr_tree_active = true
        end, { desc = 'Neotree (PR base)' })

        -- PR-ladder picker — reads .git/ladder.json (or worktree equivalent),
        -- offers each rung's PR-style diff (checkout that rung, base = previous
        -- rung's tip) plus the full fat diff and a working-tree-only view.
        local function pick_ladder_base()
            local git_dir = vim.fn.system("git rev-parse --git-dir 2>/dev/null"):gsub("%s+$", "")
            if git_dir == "" then
                vim.notify("Not in a git repo", vim.log.levels.WARN)
                return
            end

            local ladder_path = git_dir .. "/ladder.json"
            if vim.fn.filereadable(ladder_path) == 0 then
                vim.notify("No ladder state at " .. ladder_path .. " — run /pr-ladder init", vim.log.levels.WARN)
                return
            end

            local ok, ladder = pcall(vim.fn.json_decode, vim.fn.readfile(ladder_path))
            if not ok or type(ladder) ~= "table" or type(ladder.rungs) ~= "table" then
                vim.notify("Invalid ladder.json", vim.log.levels.ERROR)
                return
            end

            local base_ref = ladder.base or "main"
            local entries = {}

            -- Each rung's PR diff: checkout the rung, base = previous rung tip.
            local prev_ref = base_ref
            for i, rung in ipairs(ladder.rungs) do
                table.insert(entries, {
                    label = "rung " .. i .. ": " .. rung .. "  (vs " .. prev_ref .. ")",
                    checkout = rung,
                    base = prev_ref,
                })
                prev_ref = rung
            end

            -- Full fat diff: checkout fat branch, base = ladder base.
            if ladder.fat_branch then
                table.insert(entries, {
                    label = "full fat diff: " .. ladder.fat_branch .. "  (vs " .. base_ref .. ")",
                    checkout = ladder.fat_branch,
                    base = base_ref,
                })
            end

            -- Working tree only — no checkout, base = HEAD.
            table.insert(entries, {
                label = "uncommitted (working tree only)",
                checkout = nil,
                base = "HEAD",
            })

            vim.ui.select(entries, {
                prompt = "Ladder diff view:",
                format_item = function(e) return e.label end,
            }, function(choice)
                if not choice then return end

                if choice.checkout then
                    -- Detach HEAD at the target commit instead of claiming the
                    -- branch — avoids worktree conflicts when the branch is
                    -- checked out elsewhere, and signals viewing mode.
                    local current = vim.trim(vim.fn.system("git rev-parse HEAD"))
                    local target = vim.trim(vim.fn.system("git rev-parse " .. vim.fn.shellescape(choice.checkout) .. "^0 2>/dev/null"))
                    if vim.v.shell_error ~= 0 or target == "" then
                        vim.notify("Could not resolve ref: " .. choice.checkout, vim.log.levels.ERROR)
                        return
                    end
                    if current ~= target then
                        local result = vim.fn.system("git checkout --detach " .. vim.fn.shellescape(choice.checkout) .. " 2>&1")
                        if vim.v.shell_error ~= 0 then
                            vim.notify("Checkout failed:\n" .. result, vim.log.levels.ERROR)
                            return
                        end
                        vim.cmd('checktime')
                    end
                end

                vim.cmd('Neotree git_base=' .. choice.base)
                vim.cmd('DiffPRBase ' .. choice.base)
                pr_tree_active = true
            end)
        end
        vim.keymap.set('n', '<leader>gp', pick_ladder_base, { desc = 'Pick PR-ladder diff view' })
    end
}
