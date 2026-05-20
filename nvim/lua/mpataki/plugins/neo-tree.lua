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

        -- PR-ladder picker — reads ladder state files from
        -- <git-common-dir>/ladders/*.json, walks `git worktree list`, and
        -- presents one entry per ladder worktree (fat + each rung). Selecting
        -- an entry cds nvim to that worktree and sets the diff base to the
        -- previous rung, yielding the PR-style diff. Worktree creation is
        -- the skill's job, not the picker's. Multiple ladders coexist; the
        -- picker auto-selects the one claiming the current branch, or
        -- prompts when there's no unique match.
        local function get_worktrees()
            local worktrees = {}
            local cur = {}
            local flush = function()
                if cur.path and cur.branch then
                    worktrees[cur.branch] = cur.path
                end
                cur = {}
            end
            for _, line in ipairs(vim.fn.systemlist("git worktree list --porcelain")) do
                if line == "" then
                    flush()
                elseif line:sub(1, 9) == "worktree " then
                    cur.path = line:sub(10)
                elseif line:sub(1, 7) == "branch " then
                    cur.branch = line:sub(8):gsub("^refs/heads/", "")
                end
            end
            flush()
            return worktrees
        end

        local function show_ladder_picker(ladder, worktrees)
            local base_ref = ladder.base or "main"
            local entries = {}

            if ladder.fat_branch then
                local wt = worktrees[ladder.fat_branch]
                table.insert(entries, {
                    label = "fat: " .. ladder.fat_branch ..
                        (wt and ("  vs " .. base_ref) or "  [no worktree]"),
                    path = wt,
                    base = base_ref,
                })
            end

            local prev_ref = base_ref
            for i, rung in ipairs(ladder.rungs) do
                local wt = worktrees[rung]
                table.insert(entries, {
                    label = "rung " .. i .. ": " .. rung ..
                        (wt and ("  vs " .. prev_ref) or "  [no worktree]"),
                    path = wt,
                    base = prev_ref,
                })
                prev_ref = rung
            end

            table.insert(entries, {
                label = "HEAD  (uncommitted only in current worktree)",
                path = nil,
                base = "HEAD",
            })

            vim.ui.select(entries, {
                prompt = "Ladder view (" .. (ladder.fat_branch or "?") .. "):",
                format_item = function(e) return e.label end,
            }, function(choice)
                if not choice then return end
                if choice.path == nil and choice.base ~= "HEAD" then
                    vim.notify("No worktree for this entry — invoke /pr-ladder to set one up", vim.log.levels.WARN)
                    return
                end
                if choice.path then
                    vim.cmd('cd ' .. vim.fn.fnameescape(choice.path))
                    vim.cmd('Neotree dir=' .. vim.fn.fnameescape(choice.path) .. ' git_base=' .. choice.base)
                else
                    vim.cmd('Neotree git_base=' .. choice.base)
                end
                vim.cmd('DiffPRBase ' .. choice.base)
                pr_tree_active = true
            end)
        end

        local function pick_ladder_base()
            local git_common = vim.trim(vim.fn.system("git rev-parse --git-common-dir 2>/dev/null"))
            if git_common == "" then
                vim.notify("Not in a git repo", vim.log.levels.WARN)
                return
            end

            local ladders_dir = git_common .. "/ladders"
            if vim.fn.isdirectory(ladders_dir) == 0 then
                vim.notify("No ladders directory at " .. ladders_dir .. " — run /pr-ladder init", vim.log.levels.WARN)
                return
            end

            local files = vim.fn.glob(ladders_dir .. "/*.json", true, true)
            if #files == 0 then
                vim.notify("No ladder state files in " .. ladders_dir, vim.log.levels.WARN)
                return
            end

            local ladders = {}
            for _, file in ipairs(files) do
                local ok, data = pcall(vim.fn.json_decode, vim.fn.readfile(file))
                if ok and type(data) == "table" and type(data.rungs) == "table" then
                    data._name = vim.fn.fnamemodify(file, ":t:r")
                    table.insert(ladders, data)
                end
            end
            if #ladders == 0 then
                vim.notify("No valid ladder files in " .. ladders_dir, vim.log.levels.ERROR)
                return
            end

            local worktrees = get_worktrees()

            -- Match current branch against ladders
            local current = vim.trim(vim.fn.system("git symbolic-ref --short HEAD 2>/dev/null"))
            local matching = {}
            if current ~= "" then
                for _, l in ipairs(ladders) do
                    if l.fat_branch == current then
                        table.insert(matching, l)
                    else
                        for _, rung in ipairs(l.rungs) do
                            if rung == current then
                                table.insert(matching, l)
                                break
                            end
                        end
                    end
                end
            end

            if #matching == 1 then
                show_ladder_picker(matching[1], worktrees)
            else
                local prompt = #matching == 0
                    and "Pick a ladder (no match for current branch):"
                    or "Pick a ladder (multiple match current branch):"
                vim.ui.select(ladders, {
                    prompt = prompt,
                    format_item = function(l)
                        return l._name .. "  — fat: " .. (l.fat_branch or "?")
                    end,
                }, function(ladder)
                    if not ladder then return end
                    show_ladder_picker(ladder, worktrees)
                end)
            end
        end
        vim.keymap.set('n', '<leader>gp', pick_ladder_base, { desc = 'Pick PR-ladder view (cd + diff base)' })
    end
}
