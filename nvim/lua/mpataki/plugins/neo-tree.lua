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

        -- TODO(neo-tree-diff-bug): remove this block once upstream fixes
        -- diff.lua's name_status_job. Check on nvim-neo-tree/neo-tree.nvim
        -- — compare diff.lua:~65 vs git/init.lua status_job and
        -- git/ls-files.lua; this block can go once diff.lua wraps
        -- on_parsed the same way they do.
        --
        -- Bug: git/diff.lua name_status_job forwards on_parsed directly to
        -- git_utils.run_coroutine_on_interval, which invokes its callback
        -- as (success, ...). The other two callers wrap and unwrap success;
        -- diff.lua doesn't. Result: on_parsed receives `true` as the
        -- "status", which gets stored at worktree.status_diff[base] and
        -- later crashes _find_existing_status_code_in_git_status with
        -- "attempt to index a boolean value". Only triggers with
        -- git_base=... (e.g. <leader>gt/gT). Introduced in PR #1959.
        do
            local git_diff = require("neo-tree.git.diff")
            local git_utils = require("neo-tree.git.utils")
            local git_cmd = require("neo-tree.git.cmd")
            local git_parser = require("neo-tree.git.parser")
            local log = require("neo-tree.log")
            local utils = require("neo-tree.utils")

            git_diff.name_status_job = function(worktree_root, base, skip_bubbling, context, on_parsed)
                local cmd = git_cmd.with_args({
                    "-C", worktree_root, "diff", base, "HEAD", "--name-status", "-z",
                })
                utils.job(cmd, nil, function(code, stdout_chunks)
                    if code ~= 0 then
                        log.warn("Could not async diff HEAD vs", base)
                        return
                    end
                    local full_output = table.concat(stdout_chunks)
                    local parsing_task = coroutine.create(git_parser.parse_diff_name_status_output)
                    local first_output = {
                        coroutine.resume(
                            parsing_task,
                            worktree_root,
                            skip_bubbling,
                            utils.gsplit_plain(full_output, "\000"),
                            context
                        ),
                    }
                    git_utils.run_coroutine_on_interval(
                        parsing_task,
                        context.batch_delay,
                        first_output,
                        function(success, status_or_err)
                            if success then
                                on_parsed(status_or_err)
                            else
                                on_parsed(nil, status_or_err)
                            end
                        end
                    )
                end)
            end
        end

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
        -- <git-common-dir>/ladders/*.json. Rung branches are regular
        -- branches (no worktrees); the picker just moves HEAD in the
        -- current worktree. Selecting a rung detaches at the rung tip;
        -- selecting fat re-attaches. nvim's CWD/root never changes.
        -- Multiple ladders coexist; the picker auto-selects the one
        -- claiming the current branch, or prompts when ambiguous.
        local function show_ladder_picker(ladder)
            local base_ref = ladder.base or "main"
            local entries = {}

            if ladder.fat_branch then
                table.insert(entries, {
                    label = "fat: " .. ladder.fat_branch .. "  (re-attach, vs " .. base_ref .. ")",
                    branch = ladder.fat_branch,
                    detach = false,
                    base = base_ref,
                })
            end

            local prev_ref = base_ref
            for i, rung in ipairs(ladder.rungs) do
                table.insert(entries, {
                    label = "rung " .. i .. ": " .. rung .. "  (detach, vs " .. prev_ref .. ")",
                    branch = rung,
                    detach = true,
                    base = prev_ref,
                })
                prev_ref = rung
            end

            table.insert(entries, {
                label = "HEAD  (uncommitted only — stay)",
                branch = nil,
                base = "HEAD",
            })

            vim.ui.select(entries, {
                prompt = "Ladder view (" .. (ladder.fat_branch or "?") .. "):",
                format_item = function(e) return e.label end,
            }, function(choice)
                if not choice then return end

                if choice.branch then
                    -- Refuse to switch when working tree is dirty
                    local dirty = vim.fn.system("git status --porcelain 2>/dev/null")
                    if dirty ~= "" then
                        vim.notify("Working tree has uncommitted changes — commit or stash before switching", vim.log.levels.WARN)
                        return
                    end

                    local current = vim.trim(vim.fn.system("git rev-parse HEAD"))
                    local target = vim.trim(vim.fn.system("git rev-parse " .. vim.fn.shellescape(choice.branch) .. "^0 2>/dev/null"))
                    if target == "" then
                        vim.notify("Could not resolve branch: " .. choice.branch, vim.log.levels.ERROR)
                        return
                    end

                    if current ~= target or choice.detach == false then
                        local cmd = choice.detach
                            and ("git checkout --detach " .. vim.fn.shellescape(choice.branch))
                            or  ("git checkout " .. vim.fn.shellescape(choice.branch))
                        local result = vim.fn.system(cmd .. " 2>&1")
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

            -- Match current HEAD against ladders. Try branch-name match
            -- first (cheap); fall back to SHA match for detached HEAD.
            local current_branch = vim.trim(vim.fn.system("git symbolic-ref --short HEAD 2>/dev/null"))
            local current_sha = vim.trim(vim.fn.system("git rev-parse HEAD 2>/dev/null"))

            local function ref_sha(ref)
                if not ref or ref == "" then return "" end
                return vim.trim(vim.fn.system("git rev-parse " .. vim.fn.shellescape(ref) .. " 2>/dev/null"))
            end

            local matching = {}
            for _, l in ipairs(ladders) do
                local claimed = false
                if current_branch ~= "" then
                    if l.fat_branch == current_branch then claimed = true end
                    if not claimed then
                        for _, rung in ipairs(l.rungs) do
                            if rung == current_branch then claimed = true; break end
                        end
                    end
                end
                if not claimed and current_sha ~= "" then
                    if ref_sha(l.fat_branch) == current_sha then
                        claimed = true
                    else
                        for _, rung in ipairs(l.rungs) do
                            if ref_sha(rung) == current_sha then claimed = true; break end
                        end
                    end
                end
                if claimed then table.insert(matching, l) end
            end

            if #matching == 1 then
                show_ladder_picker(matching[1])
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
                    show_ladder_picker(ladder)
                end)
            end
        end
        vim.keymap.set('n', '<leader>gp', pick_ladder_base, { desc = 'Pick PR-ladder view (detach/re-attach + diff base)' })
    end
}
