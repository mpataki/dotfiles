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
        -- +adds/-dels per file vs the tree's git_base (<leader>gT/gF), like the
        -- <leader>gS picker but against the worktree, as the tree's status is.
        -- Cached per base; dropped on write and when neo-tree swaps in a new
        -- status table (commit, checkout, external edit).
        -- The same entry carries which changed files are linguist-generated:
        -- those get a "(gen)" tag and muted highlights (mpataki.generated).
        local generated = require('mpataki.generated')
        local stats_cache = {}
        vim.api.nvim_create_autocmd('BufWritePost', { callback = function() stats_cache = {} end })
        -- entry, repo-relative path for a file node in a tree with a git_base.
        local function stat_entry(node, state)
            for root, base in pairs(state.git_base_by_worktree or {}) do
                if base ~= 'HEAD' and node.path:sub(1, #root + 1) == root .. '/' then
                    local _, wt = require('neo-tree.git').find_existing_worktree(node.path)
                    local key = root .. '\0' .. base
                    local entry = stats_cache[key]
                    if not entry or entry.status ~= (wt and wt.status) then
                        entry = { status = wt and wt.status, files = {} }
                        local paths = {}
                        for _, l in ipairs(vim.fn.systemlist({ 'git', '-C', root, 'diff', '--numstat', base })) do
                            local add, del, file = l:match('^(%S+)\t(%S+)\t(.+)$')
                            if file then
                                entry.files[file] = { add, del }
                                table.insert(paths, file)
                            end
                        end
                        entry.gen = generated.set(root, paths)
                        stats_cache[key] = entry
                    end
                    return entry, node.path:sub(#root + 2)
                end
            end
        end
        local function is_generated(node, state)
            if node.type ~= 'file' then return false end
            local entry, rel = stat_entry(node, state)
            return entry ~= nil and entry.gen[rel] == true
        end
        local function diff_stat(_, node, state)
            if node.type ~= 'file' then return {} end
            local entry, rel = stat_entry(node, state)
            local s = entry and entry.files[rel]
            if not s then return {} end
            if not entry.gen[rel] then
                return {
                    { text = '+' .. s[1], highlight = 'diffAdded' },
                    { text = '-' .. s[2], highlight = 'diffRemoved' },
                }
            end
            return {
                { text = generated.TAG .. ' ', highlight = generated.muted('Normal') },
                { text = '+' .. s[1], highlight = generated.muted('diffAdded') },
                { text = '-' .. s[2], highlight = generated.muted('diffRemoved') },
            }
        end
        -- Wrap a source's own name component: same text, muted highlight.
        local function muted_name(orig)
            return function(config, node, state)
                local r = orig(config, node, state)
                if r and r.highlight and is_generated(node, state) then
                    r.highlight = generated.muted(r.highlight)
                end
                return r
            end
        end
        local file_renderer = vim.deepcopy(require('neo-tree.defaults').renderers.file)
        for _, c in ipairs(file_renderer) do
            if c[1] == 'container' then
                for i, inner in ipairs(c.content) do
                    if inner[1] == 'git_status' then
                        table.insert(c.content, i, { 'diff_stat', zindex = 10, align = 'right' })
                        break
                    end
                end
            end
        end

        require("neo-tree").setup({
            renderers = { file = file_renderer },
            git_status = { components = {
                diff_stat = diff_stat,
                name = muted_name(require('neo-tree.sources.git_status.components').name),
            } },
            filesystem = {
                components = {
                    diff_stat = diff_stat,
                    name = muted_name(require('neo-tree.sources.common.components').name),
                },
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

        -- TODO(neo-tree-status-cache): remove once upstream git/init.lua
        -- M.status returns the base diff on its "status_text == last_status_text"
        -- early return too. Today that path returns only the worktree status,
        -- so reopening the git_status source with git_base (<leader>gF) on an
        -- unchanged worktree lists nothing from the branch.
        -- prtree_probe.lua catches a regression either way.
        do
            local git = require("neo-tree.git")
            local status = git.status
            git.status = function(path, base_lookup, skip_bubbling, status_opts)
                local st, root, over_base = status(path, base_lookup, skip_bubbling, status_opts)
                local base = root and base_lookup and base_lookup[root]
                if st and base and not over_base then
                    over_base = require("neo-tree.git.diff").diff_name_status(root, base, skip_bubbling)
                end
                return st, root, over_base
            end
        end

        vim.keymap.set('n', '<Leader>ls', ':Neotree<CR>', { desc = 'Neotree' })
        vim.keymap.set('n', '<Leader>lS', ':Neotree position=current<CR>', { desc = 'Neotree (full window)' })

        local pr_tree_active = false
        vim.keymap.set('n', '<leader>gt', function()
            local pr = require('mpataki.review.pr')
            local root = pr.current_root()
            if root then pr.pin_base(root, nil) end
            require('mpataki.ladder_follow').stop()
            vim.cmd('Neotree git_base=HEAD')
            if pr_tree_active then
                vim.cmd('DiffReset')
                pr_tree_active = false
            end
        end, { desc = 'Neotree (HEAD)' })
        -- Same base as <leader>gS and the mini.diff overlay (pr.info: PR base,
        -- else origin/HEAD), so the tree, picker and overlay agree on what
        -- changed. Neo-tree layers uncommitted status over base..HEAD.
        local function pr_tree(source)
            local pr = require('mpataki.review.pr')
            local root = pr.current_root()
            if not root then
                vim.notify('PR tree: not in a git repo', vim.log.levels.ERROR)
                return
            end
            -- DiffPRBase first: it refreshes the cached PR identity this reads.
            vim.cmd('DiffPRBase')
            local info, err = pr.info(root)
            if not info then
                vim.notify('PR tree: ' .. err, vim.log.levels.ERROR)
                return
            end
            vim.cmd('Neotree ' .. source .. ' git_base=' .. info.base_sha)
            pr_tree_active = true
        end
        vim.keymap.set('n', '<leader>gT', function() pr_tree('filesystem') end, { desc = 'Neotree (PR base)' })
        -- Changed files only: the git_status source lists just what <leader>gS does.
        vim.keymap.set('n', '<leader>gF', function() pr_tree('git_status') end, { desc = 'Neotree changed files (PR base)' })

        -- PR-ladder picker — reads ladder files from
        -- <git-common-dir>/ladders/*.json and rung order from
        -- <git-common-dir>/gh-stack. Rung branches are regular
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
                    label = "fat: " .. ladder.fat_branch .. "  (attach, or detach if another worktree has it; vs " .. base_ref .. ")",
                    branch = ladder.fat_branch,
                    detach = false,
                    base = base_ref,
                })
            end

            local prev_ref = base_ref
            for i, rung in ipairs(ladder.rungs) do
                table.insert(entries, {
                    label = "rung " .. i .. ": " .. rung .. "  (follow, vs " .. prev_ref .. ")",
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

            -- Re-run by mpataki.ladder_follow whenever the followed branch moves.
            local function apply_choice(choice)
                local detach = choice.detach
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

                    -- Two-worktree ladders: the fat branch is attached in the
                    -- agent's worktree and git refuses a second checkout, so
                    -- view it detached at its tip instead. Rungs always detach.
                    if not detach then
                        local mine = vim.uv.fs_realpath(vim.trim(vim.fn.system("git rev-parse --show-toplevel")))
                        local path
                        for _, l in ipairs(vim.fn.systemlist("git worktree list --porcelain")) do
                            local p = l:match("^worktree (.+)$")
                            if p then path = vim.uv.fs_realpath(p) or p end
                            if l == "branch refs/heads/" .. choice.branch and path ~= mine then detach = true end
                        end
                    end

                    if current ~= target or not detach then
                        local cmd = detach
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

                -- A rung pins its base for every PR-base view (gS, gT/gF, gD,
                -- the overlay), not just this tree. merge-base, not the
                -- previous rung's tip: a lower rung that gained a commit
                -- after this one was built would otherwise show reversed.
                -- Fat and HEAD unpin.
                local pr = require('mpataki.review.pr')
                local root = pr.current_root()
                local base = choice.base
                if root and choice.detach then
                    local mb = pr.git(root, { 'merge-base', 'HEAD', choice.base })
                    if mb.code ~= 0 then
                        vim.notify('No merge base with ' .. choice.base, vim.log.levels.ERROR)
                        return
                    end
                    base = vim.trim(mb.stdout)
                    pr.pin_base(root, base)
                elseif root then
                    pr.pin_base(root, nil)
                end

                vim.cmd('Neotree git_base=' .. base)
                vim.cmd('DiffPRBase ' .. base)
                pr_tree_active = true

                -- A detached view follows its branch's new heads; an attached
                -- branch follows on its own, and HEAD has nothing to follow.
                local follow = require('mpataki.ladder_follow')
                if root and choice.branch and detach then
                    follow.start(root, choice.branch, function() apply_choice(choice) end)
                else
                    follow.stop()
                end
            end

            vim.ui.select(entries, {
                prompt = "Ladder view (" .. (ladder.fat_branch or "?") .. "):",
                kind = "menu",
                format_item = function(e) return e.label end,
            }, function(choice)
                if choice then apply_choice(choice) end
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

            -- Rung order lives in gh-stack's catalog; the ladder file only
            -- names its top rung. Legacy ladder files carry `rungs`/`base`
            -- themselves and are used as-is until the skill migrates them.
            local stacks = {}
            local stack_file = git_common .. "/gh-stack"
            if vim.fn.filereadable(stack_file) == 1 then
                local ok, catalog = pcall(vim.fn.json_decode, vim.fn.readfile(stack_file))
                if ok and type(catalog) == "table" and type(catalog.stacks) == "table" then
                    stacks = catalog.stacks
                end
            end
            local function resolve_from_stack(data)
                for _, s in ipairs(stacks) do
                    local names = {}
                    local has_top = false
                    for _, b in ipairs(s.branches or {}) do
                        table.insert(names, b.branch)
                        if b.branch == data.top then has_top = true end
                    end
                    if has_top then
                        data.rungs = names
                        data.base = s.trunk and s.trunk.branch or "main"
                        return true
                    end
                end
                return false
            end

            local ladders = {}
            for _, file in ipairs(files) do
                local ok, data = pcall(vim.fn.json_decode, vim.fn.readfile(file))
                if ok and type(data) == "table" and type(data.top) == "string" and not resolve_from_stack(data) then
                    vim.notify("Ladder " .. file .. ": top rung " .. data.top .. " not found in " .. stack_file, vim.log.levels.WARN)
                end
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
                    kind = "menu",
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
