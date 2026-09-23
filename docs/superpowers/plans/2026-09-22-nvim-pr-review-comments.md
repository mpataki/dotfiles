# nvim PR Review Comments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture GitHub PR review comments from inside nvim, push them into a *pending* GitHub review, pull everyone's comments back as virtual text + quickfix, and fix the review flow's PR-identity / cwd bugs along the way.

**Architecture:** A `mpataki.review` module tree (`pr`, `store`, `gh`, `render`, `capture`, `sync`, `init`). `pr` is the single source of PR identity and replaces three copy-pasted merge-base snippets. `store` is a pure markdown-file model. `gh` wraps `gh api` behind an injectable runner so probes use a fake. `capture` is an anchored float. `sync` is push/pull with guards.

**Tech Stack:** Neovim 0.12 Lua, `git`, `gh` CLI 2.98, lazy.nvim, mini.diff (existing), nvim-probe harness at `nvim/lua/probe.lua`.

**Spec:** `docs/superpowers/specs/2026-09-22-nvim-pr-review-comments-design.md`

## Global Constraints

- Every file under `nvim/lua/mpataki/review/` stays < 500 LOC.
- No pushing to any git remote. Commits only; small, Conventional Commits, no AI attribution trailer.
- No real `gh` writes from probes. Probes inject `require('mpataki.review.gh').runner`.
- Only `side = "RIGHT"` comments. No `event` on review creation (pending only).
- All paths sent to git/GitHub are repo-root-relative (from `git rev-parse --show-toplevel` of the *buffer's* directory), never nvim-cwd-relative.
- Probes live in `nvim/probes/review/` and run with `nvim --headless -c 'luafile <probe>' -c 'qa'` from `~/dotfiles/nvim`. Read `agent-config/skills/nvim-probe/SKILL.md` before writing one.
- Lua style: 2-space indent, `local M = {}` modules, no `vim.fn.system` string-shell calls in new code; use `vim.system({argv}, {cwd=..., text=true}):wait()`.
- Errors surface via `vim.notify(msg, vim.log.levels.ERROR)` with the failing command and first stderr line. No silent fallbacks.
- Test fixtures: each probe builds its own temp git repo under `vim.fn.tempname()` (see Task 1 helper) and never touches a real repo.

---

### Task 1: `pr.lua` — PR identity and repo-relative paths

**Files:**
- Create: `nvim/lua/mpataki/review/pr.lua`
- Create: `nvim/probes/review/fixture.lua` (shared temp-repo builder)
- Test: `nvim/probes/review/pr_probe.lua`

**Interfaces:**
- Produces:
  - `pr.root(abs_path) -> string|nil` — git toplevel for the dir containing `abs_path` (a file or dir).
  - `pr.common_dir(root) -> string` — absolute `git rev-parse --git-common-dir`.
  - `pr.relpath(root, abs_path) -> string` — path relative to root, forward slashes.
  - `pr.info(root, opts?) -> table|nil, err` — `{ root, common_dir, number?, base_ref?, head?, url?, base_sha }`. `opts.refresh = true` bypasses the cache. `base_sha` is always set (falls back to merge-base with local `main`/`master`); `number/base_ref/head/url` only when `gh pr view` succeeds.
  - `pr.clear_cache()`.
  - `pr.parse_hunk_ranges(diff_text) -> { {s=int, e=int}, ... }` — new-file line ranges from `@@ -a,b +c,d @@` headers.
  - `pr.diff_ranges(root, base_sha, head_ref, relpath) -> ranges` — runs `git diff -U3 base head -- relpath`, then `parse_hunk_ranges`.
  - `pr.in_ranges(ranges, line) -> boolean`.
  - `pr.git(root, argv) -> {code, stdout, stderr}` — thin `vim.system` wrapper used by other modules.

- [ ] **Step 1: Write the fixture helper**

`nvim/probes/review/fixture.lua`:

```lua
-- Builds a throwaway git repo for review probes. Returns { root, base_sha, head_sha }.
-- Layout: sub/dir/file.txt with 10 lines on main; branch "feature" changes line 5
-- and appends line 11. Nothing here touches a real repo.
local F = {}

local function sh(argv, cwd)
  local r = vim.system(argv, { cwd = cwd, text = true }):wait()
  assert(r.code == 0, table.concat(argv, ' ') .. ' failed: ' .. (r.stderr or ''))
  return vim.trim(r.stdout)
end

function F.repo()
  local root = vim.fn.tempname()
  vim.fn.mkdir(root .. '/sub/dir', 'p')
  -- macOS: $TMPDIR is /var/... but git reports /private/var/...; compare real paths.
  root = vim.uv.fs_realpath(root)
  sh({ 'git', 'init', '-q', '-b', 'main' }, root)
  sh({ 'git', 'config', 'user.email', 'probe@example.com' }, root)
  sh({ 'git', 'config', 'user.name', 'probe' }, root)
  sh({ 'git', 'config', 'commit.gpgsign', 'false' }, root)

  local lines = {}
  for i = 1, 10 do lines[i] = 'line ' .. i end
  vim.fn.writefile(lines, root .. '/sub/dir/file.txt')
  sh({ 'git', 'add', 'sub/dir/file.txt' }, root)
  sh({ 'git', 'commit', '-q', '-m', 'base' }, root)
  local base_sha = sh({ 'git', 'rev-parse', 'HEAD' }, root)

  sh({ 'git', 'checkout', '-q', '-b', 'feature' }, root)
  lines[5] = 'line 5 changed'
  lines[11] = 'line 11'
  vim.fn.writefile(lines, root .. '/sub/dir/file.txt')
  sh({ 'git', 'commit', '-q', '-am', 'change' }, root)
  local head_sha = sh({ 'git', 'rev-parse', 'HEAD' }, root)

  return { root = root, base_sha = base_sha, head_sha = head_sha }
end

return F
```

- [ ] **Step 2: Write the failing probe**

`nvim/probes/review/pr_probe.lua`:

```lua
package.path = vim.fn.expand('~/dotfiles/nvim/probes/review/?.lua') .. ';' .. package.path
local P = require('probe')
local F = require('fixture')
local pr = require('mpataki.review.pr')

local fx = F.repo()
local file = fx.root .. '/sub/dir/file.txt'

P.eq(pr.root(file), fx.root, 'root from file path')
P.eq(pr.root(fx.root .. '/sub/dir'), fx.root, 'root from dir path')
P.eq(pr.relpath(fx.root, file), 'sub/dir/file.txt', 'relpath is repo-relative')
P.ok(pr.common_dir(fx.root):match('/%.git$') ~= nil, 'common_dir ends in .git')

-- cwd must not matter: chdir into the subdir and resolve again
vim.fn.chdir(fx.root .. '/sub/dir')
P.eq(pr.relpath(pr.root(file), file), 'sub/dir/file.txt', 'relpath independent of cwd')

local info, err = pr.info(fx.root)
P.ok(info ~= nil, 'info resolves without a PR: ' .. tostring(err))
P.eq(info and info.base_sha, fx.base_sha, 'base_sha falls back to merge-base with main')
P.eq(info and info.number, nil, 'no PR number without gh PR')

local ranges = pr.parse_hunk_ranges(table.concat({
  'diff --git a/x b/x',
  '@@ -2,7 +2,8 @@',
  ' ctx',
  '@@ -20 +21,2 @@',
  '+a',
}, '\n'))
P.eq(#ranges, 2, 'two hunks parsed')
P.eq(ranges[1].s, 2, 'hunk1 start'); P.eq(ranges[1].e, 9, 'hunk1 end')
P.eq(ranges[2].s, 21, 'hunk2 start'); P.eq(ranges[2].e, 22, 'hunk2 end (count 2)')

local live = pr.diff_ranges(fx.root, fx.base_sha, fx.head_sha, 'sub/dir/file.txt')
P.ok(pr.in_ranges(live, 5), 'changed line 5 in diff')
P.ok(pr.in_ranges(live, 2), 'context line 2 in diff (U3)')
P.ok(pr.in_ranges(live, 11), 'appended line 11 in diff')
P.ok(not pr.in_ranges(live, 1), 'line 1 outside diff')

P.done()
```

- [ ] **Step 3: Run it, expect failure**

Run: `cd ~/dotfiles/nvim && nvim --headless -c 'luafile probes/review/pr_probe.lua' -c 'qa'; echo "exit=$?"`
Expected: error `module 'mpataki.review.pr' not found`, non-zero exit.

- [ ] **Step 4: Implement `pr.lua`**

```lua
-- PR identity for the review flow. Single source of: repo root, repo-relative
-- paths, PR number/base/head (via gh), merge-base, and diff line ranges.
-- Every path handed to git or GitHub goes through relpath(); nvim's cwd is
-- never consulted, because it is often a different directory or repo.
local M = {}

local cache = {} -- root -> info

local function run(argv, cwd)
  local r = vim.system(argv, { cwd = cwd, text = true }):wait()
  return { code = r.code, stdout = r.stdout or '', stderr = r.stderr or '' }
end

function M.git(root, argv)
  return run(vim.list_extend({ 'git' }, argv), root)
end

local function dir_of(abs_path)
  if vim.fn.isdirectory(abs_path) == 1 then return abs_path end
  return vim.fn.fnamemodify(abs_path, ':h')
end

function M.root(abs_path)
  if not abs_path or abs_path == '' then return nil end
  local r = run({ 'git', 'rev-parse', '--show-toplevel' }, dir_of(abs_path))
  if r.code ~= 0 then return nil end
  return vim.trim(r.stdout)
end

function M.common_dir(root)
  local r = M.git(root, { 'rev-parse', '--git-common-dir' })
  local d = vim.trim(r.stdout)
  if d:sub(1, 1) ~= '/' then d = root .. '/' .. d end
  return vim.fn.fnamemodify(d, ':p'):gsub('/$', '')
end

function M.relpath(root, abs_path)
  local full = vim.uv.fs_realpath(abs_path) or vim.fn.fnamemodify(abs_path, ':p')
  local rel = full:sub(#root + 2)
  return (rel:gsub('\\', '/'))
end

local function merge_base(root, ref)
  local r = M.git(root, { 'merge-base', 'HEAD', ref })
  if r.code ~= 0 then return nil end
  return vim.trim(r.stdout)
end

local function gh_pr_view(root)
  local r = run({ 'gh', 'pr', 'view', '--json', 'number,baseRefName,headRefOid,url' }, root)
  if r.code ~= 0 then return nil end
  local ok, data = pcall(vim.json.decode, r.stdout)
  if not ok then return nil end
  return data
end

function M.info(root, opts)
  opts = opts or {}
  if not opts.refresh and cache[root] then return cache[root] end

  local info = { root = root, common_dir = M.common_dir(root) }
  local pr = gh_pr_view(root)
  if pr then
    info.number = pr.number
    info.base_ref = pr.baseRefName
    info.head = pr.headRefOid
    info.url = pr.url
    info.base_sha = merge_base(root, 'origin/' .. pr.baseRefName) or merge_base(root, pr.baseRefName)
  end
  info.base_sha = info.base_sha or merge_base(root, 'main') or merge_base(root, 'master')
  if not info.base_sha then
    return nil, 'could not find merge base (no PR, no main/master)'
  end

  cache[root] = info
  return info
end

function M.clear_cache()
  cache = {}
end

function M.parse_hunk_ranges(diff_text)
  local ranges = {}
  for c, d in diff_text:gmatch('\n?@@ %-%d+,?%d* %+(%d+),?(%d*) @@') do
    local start = tonumber(c)
    local count = d == '' and 1 or tonumber(d)
    if count > 0 then
      table.insert(ranges, { s = start, e = start + count - 1 })
    end
  end
  return ranges
end

function M.diff_ranges(root, base_sha, head_ref, relpath)
  local r = M.git(root, { 'diff', '-U3', base_sha, head_ref, '--', relpath })
  if r.code ~= 0 then return {} end
  return M.parse_hunk_ranges(r.stdout)
end

function M.in_ranges(ranges, line)
  for _, h in ipairs(ranges) do
    if line >= h.s and line <= h.e then return true end
  end
  return false
end

return M
```

- [ ] **Step 5: Run the probe, expect all PASS**

Run: `cd ~/dotfiles/nvim && nvim --headless -c 'luafile probes/review/pr_probe.lua' -c 'qa'; echo "exit=$?"`
Expected: every line `PASS`, `exit=0`. If `common_dir` fails, check `git rev-parse --git-common-dir` returns `.git` (relative) inside a non-worktree repo; the code joins it to root.

- [ ] **Step 6: Commit**

```bash
cd ~/dotfiles && git add nvim/lua/mpataki/review/pr.lua nvim/probes/review/fixture.lua nvim/probes/review/pr_probe.lua
git commit -m "feat(nvim): review.pr resolves PR identity and repo-relative paths"
```

---

### Task 2: `store.lua` — pending comments file

**Files:**
- Create: `nvim/lua/mpataki/review/store.lua`
- Test: `nvim/probes/review/store_probe.lua`

**Interfaces:**
- Produces:
  - Entry shape: `{ path = string, line = int, start_line = int|nil, body = string }`.
  - Doc shape: `{ header = { repo = string|nil, head = string|nil, pushed = string|nil }, entries = { entry... } }`.
  - `store.path(common_dir, number) -> string` — `<common_dir>/reviews/<number>.md`.
  - `store.remote_path(common_dir, number) -> string` — `<common_dir>/reviews/<number>.remote.json`.
  - `store.key(entry) -> string` — `path:line` or `path:start-line`.
  - `store.parse(text) -> doc`, `store.serialize(doc) -> text`.
  - `store.read(file) -> doc` (empty doc when missing), `store.write(file, doc)` (mkdir -p).
  - `store.find(doc, path, line, start_line) -> entry|nil, index|nil`.
  - `store.upsert(doc, entry)` — replaces by key; empty/whitespace body removes.
  - `store.remove(doc, path, line, start_line)`.
  - `store.fingerprint(entries) -> hex` — `vim.fn.sha256` of sorted `key .. ':' .. body` joined by `\n`.

- [ ] **Step 1: Write the failing probe**

`nvim/probes/review/store_probe.lua`:

```lua
local P = require('probe')
local store = require('mpataki.review.store')

local common = vim.fn.tempname()
local file = store.path(common, 42)
P.eq(file, common .. '/reviews/42.md', 'store path')
P.eq(store.remote_path(common, 42), common .. '/reviews/42.remote.json', 'remote path')

local doc = store.read(file)
P.eq(#doc.entries, 0, 'missing file reads as empty doc')

store.upsert(doc, { path = 'a/b.go', line = 42, body = 'first\n\nsecond para' })
store.upsert(doc, { path = 'a/b.go', line = 15, start_line = 10, body = 'range' })
doc.header = { repo = 'o/r#42', head = 'abc123', pushed = 'deadbeef' }
store.write(file, doc)

local text = table.concat(vim.fn.readfile(file), '\n')
P.ok(text:find('<!%-%- review: o/r#42 head=abc123 pushed=deadbeef %-%->', 1) ~= nil, 'header serialized')
P.ok(text:find('\n## a/b.go:42\n', 1, true) ~= nil, 'single-line heading')
P.ok(text:find('\n## a/b.go:10-15\n', 1, true) ~= nil, 'range heading')

local back = store.read(file)
P.eq(back.header.head, 'abc123', 'header head round-trips')
P.eq(back.header.pushed, 'deadbeef', 'header pushed round-trips')
P.eq(#back.entries, 2, 'two entries round-trip')
local e = store.find(back, 'a/b.go', 42)
P.eq(e and e.body, 'first\n\nsecond para', 'multi-paragraph body round-trips')
local r = store.find(back, 'a/b.go', 15, 10)
P.eq(r and r.start_line, 10, 'range start_line round-trips')

store.upsert(back, { path = 'a/b.go', line = 42, body = 'edited' })
P.eq(store.find(back, 'a/b.go', 42).body, 'edited', 'upsert replaces by key')
P.eq(#back.entries, 2, 'upsert did not duplicate')

store.upsert(back, { path = 'a/b.go', line = 42, body = '   \n ' })
P.eq(store.find(back, 'a/b.go', 42), nil, 'blank body deletes')
P.eq(#back.entries, 1, 'one entry left')

store.remove(back, 'a/b.go', 15, 10)
P.eq(#back.entries, 0, 'remove empties')

local fp1 = store.fingerprint({ { path = 'x', line = 1, body = 'a' }, { path = 'y', line = 2, body = 'b' } })
local fp2 = store.fingerprint({ { path = 'y', line = 2, body = 'b' }, { path = 'x', line = 1, body = 'a' } })
P.eq(fp1, fp2, 'fingerprint is order-independent')
P.ok(fp1 ~= store.fingerprint({ { path = 'x', line = 1, body = 'changed' } }), 'fingerprint changes with body')

P.eq(store.parse('').header.head, nil, 'empty text parses')
P.eq(#store.parse('# junk\n\nno headings').entries, 0, 'non-entry text ignored')

P.done()
```

- [ ] **Step 2: Run it, expect failure**

Run: `cd ~/dotfiles/nvim && nvim --headless -c 'luafile probes/review/store_probe.lua' -c 'qa'; echo "exit=$?"`
Expected: `module 'mpataki.review.store' not found`, non-zero exit.

- [ ] **Step 3: Implement `store.lua`**

```lua
-- Pending review comments as a markdown file. The file is the source of truth
-- for the local draft; the capture float and push/pull read and write it.
-- Format:
--   <!-- review: owner/repo#N head=<sha> pushed=<fingerprint> -->
--   ## path:line          (or ## path:start-end)
--   body until next "## "
local M = {}

function M.path(common_dir, number)
  return common_dir .. '/reviews/' .. tostring(number) .. '.md'
end

function M.remote_path(common_dir, number)
  return common_dir .. '/reviews/' .. tostring(number) .. '.remote.json'
end

function M.key(entry)
  if entry.start_line then
    return ('%s:%d-%d'):format(entry.path, entry.start_line, entry.line)
  end
  return ('%s:%d'):format(entry.path, entry.line)
end

local function parse_header(line)
  local repo, head, pushed = line:match('^<!%-%- review: (%S+) head=(%S*) pushed=(%S*) %-%->')
  if not repo then return {} end
  return { repo = repo, head = head ~= '' and head or nil, pushed = pushed ~= '' and pushed or nil }
end

local function parse_heading(line)
  local path, a, b = line:match('^## (.-):(%d+)%-(%d+)$')
  if path then return { path = path, start_line = tonumber(a), line = tonumber(b) } end
  path, a = line:match('^## (.-):(%d+)$')
  if path then return { path = path, line = tonumber(a) } end
  return nil
end

function M.parse(text)
  local doc = { header = {}, entries = {} }
  local current, body = nil, {}

  local function flush()
    if current then
      current.body = vim.trim(table.concat(body, '\n'))
      table.insert(doc.entries, current)
    end
    current, body = nil, {}
  end

  for line in (text .. '\n'):gmatch('(.-)\n') do
    local heading = parse_heading(line)
    if heading then
      flush()
      current = heading
    elseif not current and line:match('^<!%-%- review:') then
      doc.header = parse_header(line)
    elseif current then
      table.insert(body, line)
    end
  end
  flush()
  return doc
end

function M.serialize(doc)
  local h = doc.header or {}
  local out = {
    ('<!-- review: %s head=%s pushed=%s -->'):format(h.repo or '', h.head or '', h.pushed or ''),
    '',
  }
  for _, e in ipairs(doc.entries) do
    table.insert(out, '## ' .. M.key(e))
    table.insert(out, '')
    table.insert(out, e.body)
    table.insert(out, '')
  end
  return table.concat(out, '\n') .. '\n'
end

function M.read(file)
  if vim.fn.filereadable(file) ~= 1 then
    return { header = {}, entries = {} }
  end
  return M.parse(table.concat(vim.fn.readfile(file), '\n'))
end

function M.write(file, doc)
  vim.fn.mkdir(vim.fn.fnamemodify(file, ':h'), 'p')
  vim.fn.writefile(vim.split(M.serialize(doc), '\n'), file)
end

function M.find(doc, path, line, start_line)
  local want = M.key({ path = path, line = line, start_line = start_line })
  for i, e in ipairs(doc.entries) do
    if M.key(e) == want then return e, i end
  end
  return nil, nil
end

function M.remove(doc, path, line, start_line)
  local _, i = M.find(doc, path, line, start_line)
  if i then table.remove(doc.entries, i) end
end

function M.upsert(doc, entry)
  local body = vim.trim(entry.body or '')
  local _, i = M.find(doc, entry.path, entry.line, entry.start_line)
  if body == '' then
    if i then table.remove(doc.entries, i) end
    return
  end
  local e = { path = entry.path, line = entry.line, start_line = entry.start_line, body = body }
  if i then doc.entries[i] = e else table.insert(doc.entries, e) end
end

function M.fingerprint(entries)
  local parts = {}
  for _, e in ipairs(entries) do
    table.insert(parts, M.key(e) .. ':' .. vim.trim(e.body or ''))
  end
  table.sort(parts)
  return vim.fn.sha256(table.concat(parts, '\n'))
end

return M
```

- [ ] **Step 4: Run the probe, expect all PASS**

Run: `cd ~/dotfiles/nvim && nvim --headless -c 'luafile probes/review/store_probe.lua' -c 'qa'; echo "exit=$?"`
Expected: all `PASS`, `exit=0`.

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles && git add nvim/lua/mpataki/review/store.lua nvim/probes/review/store_probe.lua
git commit -m "feat(nvim): review.store models the pending comments file"
```

---

### Task 3: Route existing review commands through `pr.lua` (cwd fix, dedupe)

**Files:**
- Modify: `nvim/lua/mpataki/plugins/minidiff.lua:33-92` (`set_pr_ref_for_buf`, `DiffPRBase`)
- Modify: `nvim/lua/mpataki/plugins/diffview.lua:51-59` (`DiffviewPR`)
- Modify: `nvim/lua/mpataki/plugins/telescope.lua:176-188` (`git_pr_files` base resolution)
- Test: `nvim/probes/review/diffprbase_probe.lua`

**Interfaces:**
- Consumes: `pr.root`, `pr.relpath`, `pr.info`, `pr.git` from Task 1.

- [ ] **Step 1: Write the failing probe** (regression for the cwd bug)

`nvim/probes/review/diffprbase_probe.lua`:

```lua
package.path = vim.fn.expand('~/dotfiles/nvim/probes/review/?.lua') .. ';' .. package.path
local P = require('probe')
local F = require('fixture')

local fx = F.repo()
-- The bug: cwd is a subdirectory, so ':.' paths are wrong for `git show`.
vim.fn.chdir(fx.root .. '/sub/dir')
vim.cmd('edit ' .. vim.fn.fnameescape(fx.root .. '/sub/dir/file.txt'))
P.wait(500)

vim.cmd('DiffPRBase')
P.wait(1500, function()
  local d = require('mini.diff').get_buf_data(0)
  return d and d.ref_text and d.ref_text:find('line 5\n', 1, true) ~= nil
end)

local data = require('mini.diff').get_buf_data(0)
P.ok(data ~= nil, 'mini.diff attached')
P.ok(data and data.ref_text and data.ref_text:find('line 5\n', 1, true) ~= nil,
  'ref text is the base file, not empty (cwd-independent path)')
P.ok(data and #data.hunks >= 1 and #data.hunks <= 2, 'hunks reflect base..HEAD, got ' .. tostring(data and #data.hunks))

P.done()
```

- [ ] **Step 2: Run it, expect failure**

Run: `cd ~/dotfiles/nvim && nvim --headless -c 'luafile probes/review/diffprbase_probe.lua' -c 'qa'; echo "exit=$?"`
Expected: the "ref text is the base file" check FAILs (ref text empty → all lines added, hunk count wrong), non-zero exit. If it passes unexpectedly, confirm the cwd was actually changed (`vim.fn.getcwd()`), because the bug only shows from a subdirectory.

- [ ] **Step 3: Rewrite the PR-review block in `minidiff.lua`**

Replace lines 33–92 (from `-- PR review mode` through the end of the `DiffPRBase` command) with:

```lua
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
          local root = pr.root(vim.api.nvim_buf_get_name(0)) or pr.root(vim.fn.getcwd())
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
            local info, err = pr.info(root)
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
```

Leave `DiffReset` as is.

- [ ] **Step 4: Rewrite `DiffviewPR` in `diffview.lua`**

Replace lines 51–59 with:

```lua
    vim.api.nvim_create_user_command('DiffviewPR', function()
      local pr = require('mpataki.review.pr')
      local root = pr.root(vim.api.nvim_buf_get_name(0)) or pr.root(vim.fn.getcwd())
      local info, err = root and pr.info(root)
      if not info then
        vim.notify('DiffviewPR: ' .. (err or 'not in a git repo'), vim.log.levels.ERROR)
        return
      end
      vim.cmd('DiffviewOpen ' .. info.base_sha .. '...HEAD')
      vim.cmd('DiffPRBase')
    end, { desc = 'Open Diffview against base branch (PR diff)' })
```

- [ ] **Step 5: Rewrite base resolution in `git_pr_files` in `telescope.lua`**

Replace lines 182–188 (`local base = vim.fn.system(...)` through `vim.cmd('DiffPRBase')`) with:

```lua
			local pr = require('mpataki.review.pr')
			local root = pr.root(vim.api.nvim_buf_get_name(0)) or pr.root(vim.fn.getcwd())
			local info, err = root and pr.info(root)
			if not info then
				vim.notify('PR files: ' .. (err or 'not in a git repo'), vim.log.levels.ERROR)
				return
			end
			local base = info.base_sha

			vim.cmd('DiffPRBase')
```

The rest of the function keeps using `base`. Note the two `vim.fn.systemlist({ 'git', ... })` calls in that function run in nvim's cwd; leave them (cwd-relative file names are what the picker displays and opens), but note it in the commit body as a known limitation.

- [ ] **Step 6: Run the probe and the load gate, expect PASS**

Run:
```bash
cd ~/dotfiles/nvim && nvim --headless -c 'luafile probes/review/diffprbase_probe.lua' -c 'qa'; echo "exit=$?"
nvim --headless -c 'lua print(pcall(require, "diffview") and "diffview ok" or "diffview FAIL")' -c 'lua print(pcall(require, "telescope") and "telescope ok" or "telescope FAIL")' -c 'qa'
```
Expected: all `PASS`, `exit=0`, both `ok`.

- [ ] **Step 7: Commit**

```bash
cd ~/dotfiles && git add nvim/lua/mpataki/plugins/minidiff.lua nvim/lua/mpataki/plugins/diffview.lua nvim/lua/mpataki/plugins/telescope.lua nvim/probes/review/diffprbase_probe.lua
git commit -m "fix(nvim): resolve PR base via review.pr; repo-relative paths for git show" -m "DiffPRBase built the path with fnamemodify(':.'), which is nvim-cwd-relative; git show needs repo-relative. From a subdirectory every file rendered as fully added. Merge-base logic was also duplicated in three places; all three now read review.pr.info()."
```

---

### Task 4: `gh.lua` — GitHub calls behind an injectable runner

**Files:**
- Create: `nvim/lua/mpataki/review/gh.lua`
- Test: `nvim/probes/review/gh_probe.lua`

**Interfaces:**
- Consumes: store entry shape from Task 2.
- Produces:
  - `gh.runner` — `function(argv, opts) -> { code, stdout, stderr }`, `opts = { cwd = string, stdin = string|nil }`. Default uses `vim.system`. Probes replace it.
  - `gh.api(root, args, opts?) -> decoded|nil, err` — runs `gh api <args...>`; `opts.input` (table) is JSON-encoded and passed via `--input -`; `opts.paginate` adds `--paginate --slurp`.
  - `gh.login(root) -> string|nil, err`.
  - Thread shape: `{ id, path, line, start_line, side, body, author, in_reply_to_id, html_url, review_id }`.
  - `gh.threads(root, number) -> threads|nil, err`.
  - `gh.pending_review(root, number, login) -> { id, comments = { entry... } }|nil, err` — `nil, nil` when no pending review.
  - `gh.delete_review(root, number, review_id) -> ok, err`.
  - `gh.create_pending(root, number, head_sha, entries) -> review_id|nil, err`.

- [ ] **Step 1: Write the failing probe (fake runner)**

`nvim/probes/review/gh_probe.lua`:

```lua
local P = require('probe')
local gh = require('mpataki.review.gh')

local calls = {}
local canned = {}
-- Longest matching pattern wins, so 'pulls/7/reviews/55/comments' beats
-- 'pulls/7/reviews', and 'POST repos/.../pulls/7/reviews' beats both.
gh.runner = function(argv, opts)
  table.insert(calls, { argv = argv, opts = opts })
  local key = table.concat(argv, ' ')
  local best, best_len = nil, -1
  for pat, resp in pairs(canned) do
    if key:find(pat, 1, true) and #pat > best_len then best, best_len = resp, #pat end
  end
  if best then return best end
  return { code = 1, stdout = '', stderr = 'no canned response for: ' .. key }
end

local function last() return calls[#calls] end

canned['user'] = { code = 0, stdout = '{"login":"mpataki"}', stderr = '' }
P.eq(gh.login('/r'), 'mpataki', 'login parsed')
P.eq(last().opts.cwd, '/r', 'runs in repo root')

canned['pulls/7/comments'] = { code = 0, stdout = vim.json.encode({ {
  { id = 1, path = 'a.go', line = 3, start_line = vim.NIL, side = 'RIGHT', body = 'hi',
    user = { login = 'bob' }, in_reply_to_id = vim.NIL, html_url = 'u1', pull_request_review_id = 99 },
  { id = 2, path = 'a.go', line = vim.NIL, original_line = 8, side = 'LEFT', body = 'old',
    user = { login = 'amy' }, in_reply_to_id = 1, html_url = 'u2', pull_request_review_id = 99 },
} }), stderr = '' }
local threads = gh.threads('/r', 7)
P.eq(#threads, 2, 'two threads')
P.eq(threads[1].author, 'bob', 'author flattened')
P.eq(threads[1].start_line, nil, 'NIL start_line becomes nil')
P.eq(threads[2].line, 8, 'LEFT comment falls back to original_line')
P.eq(threads[2].in_reply_to_id, 1, 'reply id kept')
P.ok(vim.tbl_contains(last().argv, '--paginate'), 'threads paginate')

canned['pulls/7/reviews/55/comments'] = { code = 0, stdout = vim.json.encode({ {
  { path = 'a.go', line = 3, start_line = vim.NIL, body = 'draft one' },
  { path = 'b.go', line = 20, start_line = 18, body = 'draft two' },
} }), stderr = '' }
canned['pulls/7/reviews'] = { code = 0, stdout = vim.json.encode({ {
  { id = 54, state = 'APPROVED', user = { login = 'mpataki' } },
  { id = 55, state = 'PENDING', user = { login = 'mpataki' } },
  { id = 56, state = 'PENDING', user = { login = 'someone' } },
} }), stderr = '' }
local pending = gh.pending_review('/r', 7, 'mpataki')
P.eq(pending and pending.id, 55, 'finds my pending review only')
P.eq(pending and #pending.comments, 2, 'pending comments loaded')
P.eq(pending and pending.comments[2].start_line, 18, 'range start kept')

canned['pulls/8/reviews'] = { code = 0, stdout = '[[]]', stderr = '' }
local none, err = gh.pending_review('/r', 8, 'mpataki')
P.eq(none, nil, 'no pending review → nil'); P.eq(err, nil, '…and no error')

canned['DELETE repos/{owner}/{repo}/pulls/7/reviews/55'] = { code = 0, stdout = '', stderr = '' }
P.ok(gh.delete_review('/r', 7, 55), 'delete ok')
P.ok(table.concat(last().argv, ' '):find('pulls/7/reviews/55', 1, true) ~= nil, 'delete targets review id')

canned['POST repos/{owner}/{repo}/pulls/7/reviews'] = { code = 0, stdout = '{"id":77}', stderr = '' }
local id = gh.create_pending('/r', 7, 'headsha', {
  { path = 'a.go', line = 3, body = 'x' },
  { path = 'b.go', line = 20, start_line = 18, body = 'y' },
})
P.eq(id, 77, 'create returns review id')
local sent = vim.json.decode(last().opts.stdin)
P.eq(sent.commit_id, 'headsha', 'commit_id sent')
P.eq(sent.event, nil, 'no event → pending')
P.eq(#sent.comments, 2, 'two comments')
P.eq(sent.comments[1].side, 'RIGHT', 'side RIGHT')
P.eq(sent.comments[1].start_line, nil, 'no start_line on single')
P.eq(sent.comments[2].start_line, 18, 'start_line on range')
P.eq(sent.comments[2].start_side, 'RIGHT', 'start_side on range')
P.ok(vim.tbl_contains(last().argv, '--input'), 'uses --input')

canned['POST repos/{owner}/{repo}/pulls/7/reviews'] = { code = 1, stdout = '', stderr = 'HTTP 422: Unprocessable\nmore' }
local bad, berr = gh.create_pending('/r', 7, 'headsha', { { path = 'a.go', line = 3, body = 'x' } })
P.eq(bad, nil, 'error returns nil')
P.ok(berr and berr:find('HTTP 422', 1, true) ~= nil, 'error carries first stderr line')

P.done()
```

- [ ] **Step 2: Run it, expect failure**

Run: `cd ~/dotfiles/nvim && nvim --headless -c 'luafile probes/review/gh_probe.lua' -c 'qa'; echo "exit=$?"`
Expected: `module 'mpataki.review.gh' not found`.

- [ ] **Step 3: Implement `gh.lua`**

```lua
-- GitHub access for the review flow, all through `gh api`. The runner is
-- injectable so probes substitute a fake; nothing here is exercised against
-- GitHub in tests. `{owner}/{repo}` placeholders resolve from the cwd's remote,
-- which is why every call runs with cwd = repo root.
local M = {}

function M.runner(argv, opts)
  local r = vim.system(argv, { cwd = opts.cwd, stdin = opts.stdin, text = true }):wait()
  return { code = r.code, stdout = r.stdout or '', stderr = r.stderr or '' }
end

local function first_line(s)
  return (vim.trim(s or ''):match('^[^\n]*'))
end

local function nilify(v)
  if v == vim.NIL then return nil end
  return v
end

function M.api(root, args, opts)
  opts = opts or {}
  local argv = { 'gh', 'api' }
  vim.list_extend(argv, args)
  local stdin
  if opts.input then
    vim.list_extend(argv, { '--input', '-' })
    stdin = vim.json.encode(opts.input)
  end
  if opts.paginate then
    vim.list_extend(argv, { '--paginate', '--slurp' })
  end
  local r = M.runner(argv, { cwd = root, stdin = stdin })
  if r.code ~= 0 then
    return nil, ('gh api %s: %s'):format(args[1] or '', first_line(r.stderr))
  end
  if vim.trim(r.stdout) == '' then return {}, nil end
  local ok, data = pcall(vim.json.decode, r.stdout)
  if not ok then return nil, 'gh api: bad JSON: ' .. first_line(r.stdout) end
  if opts.paginate then
    -- --slurp wraps pages in an outer array; flatten one level.
    local flat = {}
    for _, page in ipairs(data) do vim.list_extend(flat, page) end
    return flat, nil
  end
  return data, nil
end

function M.login(root)
  local data, err = M.api(root, { 'user' })
  if not data then return nil, err end
  return data.login, nil
end

local function endpoint(number, suffix)
  return ('repos/{owner}/{repo}/pulls/%d%s'):format(number, suffix or '')
end

function M.threads(root, number)
  local data, err = M.api(root, { endpoint(number, '/comments') }, { paginate = true })
  if not data then return nil, err end
  local out = {}
  for _, c in ipairs(data) do
    table.insert(out, {
      id = c.id,
      path = c.path,
      line = nilify(c.line) or nilify(c.original_line),
      start_line = nilify(c.start_line),
      side = nilify(c.side) or 'RIGHT',
      body = c.body or '',
      author = c.user and c.user.login or '?',
      in_reply_to_id = nilify(c.in_reply_to_id),
      html_url = c.html_url,
      review_id = nilify(c.pull_request_review_id),
    })
  end
  return out, nil
end

function M.pending_review(root, number, login)
  local reviews, err = M.api(root, { endpoint(number, '/reviews') }, { paginate = true })
  if not reviews then return nil, err end
  local mine
  for _, r in ipairs(reviews) do
    if r.state == 'PENDING' and r.user and r.user.login == login then mine = r end
  end
  if not mine then return nil, nil end

  local comments, cerr = M.api(root, { endpoint(number, '/reviews/' .. mine.id .. '/comments') }, { paginate = true })
  if not comments then return nil, cerr end
  local entries = {}
  for _, c in ipairs(comments) do
    table.insert(entries, {
      path = c.path,
      line = nilify(c.line) or nilify(c.original_line),
      start_line = nilify(c.start_line),
      body = c.body or '',
    })
  end
  return { id = mine.id, comments = entries }, nil
end

function M.delete_review(root, number, review_id)
  local _, err = M.api(root, { '-X', 'DELETE', endpoint(number, '/reviews/' .. review_id) })
  if err then return false, err end
  return true, nil
end

function M.create_pending(root, number, head_sha, entries)
  local comments = {}
  for _, e in ipairs(entries) do
    local c = { path = e.path, line = e.line, side = 'RIGHT', body = e.body }
    if e.start_line then
      c.start_line = e.start_line
      c.start_side = 'RIGHT'
    end
    table.insert(comments, c)
  end
  local data, err = M.api(root, { '-X', 'POST', endpoint(number, '/reviews') },
    { input = { commit_id = head_sha, comments = comments } })
  if not data then return nil, err end
  return data.id, nil
end

return M
```

- [ ] **Step 4: Run the probe, expect all PASS**

Run: `cd ~/dotfiles/nvim && nvim --headless -c 'luafile probes/review/gh_probe.lua' -c 'qa'; echo "exit=$?"`
Expected: all `PASS`, `exit=0`.

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles && git add nvim/lua/mpataki/review/gh.lua nvim/probes/review/gh_probe.lua
git commit -m "feat(nvim): review.gh wraps pending-review GitHub calls with an injectable runner"
```

---

### Task 5: `render.lua` — virtual lines and quickfix

**Files:**
- Create: `nvim/lua/mpataki/review/render.lua`
- Test: `nvim/probes/review/render_probe.lua`

**Interfaces:**
- Consumes: store entries (Task 2), thread shape (Task 4).
- Produces:
  - `render.ns` — namespace id.
  - `render.render(buf, relpath, entries, threads)` — clears and sets extmarks for entries + threads whose `path == relpath`. Skips threads with `side == 'LEFT'` or no `line`.
  - `render.clear(buf)`.
  - `render.quickfix(root, entries, threads)` — replaces the quickfix list; pending first, then threads; `:copen` is the caller's job.
  - Highlight groups `ReviewPending` → `DiagnosticVirtualTextWarn`, `ReviewRemote` → `Comment` (default links, defined on load).

- [ ] **Step 1: Write the failing probe**

`nvim/probes/review/render_probe.lua`:

```lua
local P = require('probe')
local render = require('mpataki.review.render')

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'l1', 'l2', 'l3', 'l4', 'l5' })

local entries = {
  { path = 'a.go', line = 2, body = 'pending one\nsecond line' },
  { path = 'other.go', line = 2, body = 'not this file' },
}
local threads = {
  { id = 1, path = 'a.go', line = 4, side = 'RIGHT', body = 'remote', author = 'bob' },
  { id = 2, path = 'a.go', line = 3, side = 'LEFT', body = 'old side', author = 'amy' },
  { id = 3, path = 'a.go', line = nil, side = 'RIGHT', body = 'no line', author = 'cat' },
}

render.render(buf, 'a.go', entries, threads)
local marks = vim.api.nvim_buf_get_extmarks(buf, render.ns, 0, -1, { details = true })
P.eq(#marks, 2, 'one pending + one RIGHT remote rendered')

local by_row = {}
for _, m in ipairs(marks) do by_row[m[2]] = m[4] end
P.ok(by_row[1] ~= nil, 'pending at row 1 (line 2)')
P.eq(#by_row[1].virt_lines, 2, 'pending body renders two virt lines')
P.eq(by_row[1].virt_lines[1][1][2], 'ReviewPending', 'pending highlight')
P.ok(by_row[3] ~= nil, 'remote at row 3 (line 4)')
P.ok(by_row[3].virt_lines[1][1][1]:find('@bob', 1, true) ~= nil, 'remote prefixed with author')
P.eq(by_row[3].virt_lines[1][1][2], 'ReviewRemote', 'remote highlight')

render.render(buf, 'a.go', {}, {})
P.eq(#vim.api.nvim_buf_get_extmarks(buf, render.ns, 0, -1, {}), 0, 're-render clears old marks')

render.quickfix('/root', entries, threads)
local qf = vim.fn.getqflist()
P.eq(#qf, 5, 'all entries and threads listed')
P.eq(qf[1].text:sub(1, 9), '[pending]', 'pending marked')
P.eq(vim.fn.bufname(qf[1].bufnr), '/root/a.go', 'quickfix path is root-joined')
P.eq(qf[1].lnum, 2, 'pending lnum')
P.ok(qf[3].text:find('@bob', 1, true) ~= nil, 'remote text has author')
P.eq(qf[5].lnum, 1, 'thread with no line lands on line 1')
P.ok(vim.fn.hlexists('ReviewPending') == 1, 'ReviewPending defined')

P.done()
```

- [ ] **Step 2: Run it, expect failure**

Run: `cd ~/dotfiles/nvim && nvim --headless -c 'luafile probes/review/render_probe.lua' -c 'qa'; echo "exit=$?"`
Expected: `module 'mpataki.review.render' not found`.

- [ ] **Step 3: Implement `render.lua`**

```lua
-- Draws pending and remote comments as virtual lines under their anchor line
-- and fills the quickfix list. Pure presentation: no git, no gh, no file IO.
local M = {}

M.ns = vim.api.nvim_create_namespace('mpataki_review')

vim.api.nvim_set_hl(0, 'ReviewPending', { default = true, link = 'DiagnosticVirtualTextWarn' })
vim.api.nvim_set_hl(0, 'ReviewRemote', { default = true, link = 'Comment' })

local function virt_lines(prefix, body, hl)
  local lines = {}
  for i, l in ipairs(vim.split(body, '\n', { plain = true })) do
    local lead = i == 1 and prefix or string.rep(' ', #prefix)
    table.insert(lines, { { lead .. l, hl } })
  end
  return lines
end

local function mark(buf, line, lines)
  local count = vim.api.nvim_buf_line_count(buf)
  if line < 1 or line > count then return end
  vim.api.nvim_buf_set_extmark(buf, M.ns, line - 1, 0, { virt_lines = lines })
end

function M.clear(buf)
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
end

function M.render(buf, relpath, entries, threads)
  M.clear(buf)
  for _, e in ipairs(entries or {}) do
    if e.path == relpath then
      mark(buf, e.line, virt_lines('  ┃ [pending] ', e.body, 'ReviewPending'))
    end
  end
  for _, t in ipairs(threads or {}) do
    if t.path == relpath and t.line and t.side ~= 'LEFT' then
      mark(buf, t.line, virt_lines('  ┃ @' .. t.author .. ': ', t.body, 'ReviewRemote'))
    end
  end
end

local function first_line(s)
  return (vim.split(s or '', '\n', { plain = true })[1])
end

function M.quickfix(root, entries, threads)
  local items = {}
  for _, e in ipairs(entries or {}) do
    table.insert(items, {
      filename = root .. '/' .. e.path,
      lnum = e.line,
      text = '[pending] ' .. first_line(e.body),
    })
  end
  for _, t in ipairs(threads or {}) do
    table.insert(items, {
      filename = root .. '/' .. t.path,
      lnum = t.line or 1,
      text = '@' .. t.author .. ': ' .. first_line(t.body),
    })
  end
  vim.fn.setqflist({}, ' ', { title = 'PR review comments', items = items })
end

return M
```

- [ ] **Step 4: Run the probe, expect all PASS**

Run: `cd ~/dotfiles/nvim && nvim --headless -c 'luafile probes/review/render_probe.lua' -c 'qa'; echo "exit=$?"`
Expected: all `PASS`, `exit=0`.

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles && git add nvim/lua/mpataki/review/render.lua nvim/probes/review/render_probe.lua
git commit -m "feat(nvim): review.render draws comments as virtual lines and quickfix"
```

---

### Task 6: `capture.lua` + `init.lua` — float, commands, keymaps, wiring

**Files:**
- Create: `nvim/lua/mpataki/review/capture.lua`
- Create: `nvim/lua/mpataki/review/init.lua`
- Modify: `nvim/lua/mpataki/init.lua` (append `require("mpataki.review").setup()`)
- Test: `nvim/probes/review/capture_probe.lua`

**Interfaces:**
- Consumes: `pr.*` (Task 1), `store.*` (Task 2), `render.*` (Task 5).
- Produces:
  - `capture.open(opts)` — `opts = { title = string, body = string, on_save = function(body) }`. Opens the float below the cursor; `:w`/`<C-s>` calls `on_save(body)` and closes; `q` closes without calling it. Returns the float's `win` and `buf`.
  - `review.context(bufnr?) -> ctx|nil, err` — `{ root, info, relpath, file = store path, remote_file }`. `nil, err` when the buffer has no file, no repo, or no PR number.
  - `review.comment()` — `:ReviewComment` (normal + visual).
  - `review.render_current()` — `:ReviewRender`.
  - `review.quickfix()` — `:ReviewQuickfix`.
  - `review.open_file()` — `:ReviewOpen`.
  - `review.setup()` — commands, keymaps (`<leader>gc` comment n+v, `<leader>gC` quickfix), `BufWinEnter` render autocmd.
  - `review.load_threads(ctx) -> threads` — reads `remote_file` JSON, `{}` when absent (used by Task 7 too).

- [ ] **Step 1: Write the failing probe**

`nvim/probes/review/capture_probe.lua`:

```lua
package.path = vim.fn.expand('~/dotfiles/nvim/probes/review/?.lua') .. ';' .. package.path
local P = require('probe')
local F = require('fixture')
local pr = require('mpataki.review.pr')
local store = require('mpataki.review.store')
local render = require('mpataki.review.render')
local review = require('mpataki.review')

-- Capture notifications directly; nvim-notify would otherwise swallow them.
local notes = {}
vim.notify = function(msg) table.insert(notes, msg) end
local function last_note() return notes[#notes] or '' end

-- Pretend the fixture repo is PR #7 by seeding pr's cache: no gh in probes.
local fx = F.repo()
pr.clear_cache()
local info = pr.info(fx.root)
info.number = 7
info.head = fx.head_sha
info.url = 'https://example.invalid/pr/7'

vim.cmd('edit ' .. vim.fn.fnameescape(fx.root .. '/sub/dir/file.txt'))
local code_buf = vim.api.nvim_get_current_buf()
local code_win = vim.api.nvim_get_current_win()
local ctx, err = review.context(code_buf)
P.ok(ctx ~= nil, 'context resolves: ' .. tostring(err))
P.eq(ctx and ctx.relpath, 'sub/dir/file.txt', 'context relpath')
P.eq(ctx and ctx.file, store.path(info.common_dir, 7), 'context store file')

-- Line 1 is outside the diff: refuse.
vim.api.nvim_win_set_cursor(code_win, { 1, 0 })
review.comment()
P.eq(vim.api.nvim_get_current_win(), code_win, 'no float outside diff')
P.ok(last_note():find('not in the PR diff', 1, true) ~= nil, 'refusal message')

-- Line 5 is changed: float opens, write body, :w saves.
vim.api.nvim_win_set_cursor(code_win, { 5, 0 })
review.comment()
local float_win = vim.api.nvim_get_current_win()
P.ok(float_win ~= code_win, 'float opened')
P.eq(vim.api.nvim_win_get_config(float_win).relative, 'cursor', 'anchored to cursor')
P.eq(vim.bo.filetype, 'markdown', 'float is markdown')
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'looks wrong', '', 'see above' })
vim.cmd('write')
P.wait(200)
P.eq(vim.api.nvim_get_current_win(), code_win, 'float closed after :w')

local doc = store.read(ctx.file)
P.eq(#doc.entries, 1, 'entry saved')
P.eq(doc.entries[1].line, 5, 'anchored line 5')
P.eq(doc.entries[1].body, 'looks wrong\n\nsee above', 'body saved')
P.eq(doc.header.repo, nil, 'header repo unset until push sets it')
P.eq(#vim.api.nvim_buf_get_extmarks(code_buf, render.ns, 0, -1, {}), 1, 'rendered after save')

-- Reopen on the same line: body preloaded; q cancels without change.
review.comment()
P.eq(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n'), 'looks wrong\n\nsee above', 'existing body preloaded')
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>q', true, false, true), 'x', false)
P.wait(200)
P.eq(vim.api.nvim_get_current_win(), code_win, 'q closes float')
P.eq(store.read(ctx.file).entries[1].body, 'looks wrong\n\nsee above', 'q left entry unchanged')

-- Visual range 9..11 → range entry.
vim.api.nvim_win_set_cursor(code_win, { 9, 0 })
vim.cmd('normal! V2j')
vim.cmd("'<,'>ReviewComment")
P.wait(100)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'range note' })
vim.cmd('write')
P.wait(200)
local r = store.find(store.read(ctx.file), 'sub/dir/file.txt', 11, 9)
P.ok(r ~= nil, 'range entry saved as 9-11')

-- Empty body deletes.
vim.api.nvim_win_set_cursor(code_win, { 5, 0 })
review.comment()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { '' })
vim.cmd('write')
P.wait(200)
P.eq(store.find(store.read(ctx.file), 'sub/dir/file.txt', 5), nil, 'empty body deleted entry')

review.quickfix()
P.eq(#vim.fn.getqflist(), 1, 'quickfix lists remaining entry')

P.ok(vim.fn.maparg('<leader>gc', 'n') ~= '', '<leader>gc mapped (n)')
P.ok(vim.fn.maparg('<leader>gc', 'x') ~= '', '<leader>gc mapped (v)')
P.ok(vim.fn.exists(':ReviewPush') == 2, ':ReviewPush exists')
P.ok(vim.fn.exists(':ReviewPull') == 2, ':ReviewPull exists')

P.done()
```

- [ ] **Step 2: Run it, expect failure**

Run: `cd ~/dotfiles/nvim && nvim --headless -c 'luafile probes/review/capture_probe.lua' -c 'qa'; echo "exit=$?"`
Expected: `module 'mpataki.review' not found`.

- [ ] **Step 3: Implement `capture.lua`**

```lua
-- Anchored float for authoring one review comment. Owns nothing but the
-- window: the caller supplies the initial body and receives the final one.
-- `:w` works because the buffer is `acwrite` and BufWriteCmd intercepts it.
local M = {}

local function close(win)
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

function M.open(opts)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'acwrite'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'markdown'
  vim.api.nvim_buf_set_name(buf, 'review://' .. opts.title)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(opts.body or '', '\n', { plain = true }))

  local width = math.min(80, math.max(40, vim.o.columns - 10))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'cursor',
    row = 1,
    col = 0,
    width = width,
    height = 6,
    style = 'minimal',
    border = 'rounded',
    title = ' ' .. opts.title .. ' ',
    title_pos = 'left',
  })
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true

  local function save()
    local body = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
    vim.bo[buf].modified = false
    close(win)
    opts.on_save(body)
  end

  vim.api.nvim_create_autocmd('BufWriteCmd', { buffer = buf, callback = save })
  vim.keymap.set({ 'n', 'i' }, '<C-s>', save, { buffer = buf })
  vim.keymap.set('n', 'q', function()
    vim.bo[buf].modified = false
    close(win)
  end, { buffer = buf })

  vim.cmd('startinsert')
  return win, buf
end

return M
```

- [ ] **Step 4: Implement `init.lua`**

```lua
-- Review comments from nvim: commands, keymaps, and glue between pr/store/
-- render/capture. Push and pull live in sync.lua (Task 7) but are registered
-- here so the command surface is in one place.
local pr = require('mpataki.review.pr')
local store = require('mpataki.review.store')
local render = require('mpataki.review.render')
local capture = require('mpataki.review.capture')

local M = {}

local function notify_err(msg)
  vim.notify('review: ' .. msg, vim.log.levels.ERROR)
end

function M.context(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == '' or vim.bo[bufnr].buftype ~= '' then return nil, 'buffer has no file' end
  local root = pr.root(path)
  if not root then return nil, 'not in a git repo' end
  local info, err = pr.info(root)
  if not info then return nil, err end
  if not info.number then return nil, 'no PR for this branch (gh pr view found none)' end
  return {
    root = root,
    info = info,
    relpath = pr.relpath(root, path),
    file = store.path(info.common_dir, info.number),
    remote_file = store.remote_path(info.common_dir, info.number),
  }
end

function M.load_threads(ctx)
  if vim.fn.filereadable(ctx.remote_file) ~= 1 then return {} end
  local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(ctx.remote_file), '\n'))
  if not ok or type(data) ~= 'table' then return {} end
  return data
end

local function render_buf(bufnr, ctx)
  local doc = store.read(ctx.file)
  render.render(bufnr, ctx.relpath, doc.entries, M.load_threads(ctx))
end

function M.render_current()
  local bufnr = vim.api.nvim_get_current_buf()
  local ctx = M.context(bufnr)
  if not ctx then return end
  render_buf(bufnr, ctx)
end

local function anchor_from_range(range)
  if not range or range.range == 0 then
    local line = vim.api.nvim_win_get_cursor(0)[1]
    return line, nil
  end
  local s, e = range.line1, range.line2
  if s == e then return s, nil end
  return e, s
end

-- opts: command opts (range/line1/line2) or nil for a plain call.
function M.comment(opts)
  local bufnr = vim.api.nvim_get_current_buf()
  local ctx, err = M.context(bufnr)
  if not ctx then return notify_err(err) end

  local line, start_line = anchor_from_range(opts)
  local ranges = pr.diff_ranges(ctx.root, ctx.info.base_sha, ctx.info.head or 'HEAD', ctx.relpath)
  if not pr.in_ranges(ranges, line) or (start_line and not pr.in_ranges(ranges, start_line)) then
    return notify_err(('line %d is not in the PR diff; GitHub only anchors comments inside hunks (+3 context)'):format(line))
  end

  local doc = store.read(ctx.file)
  local existing = store.find(doc, ctx.relpath, line, start_line)
  local title = store.key({ path = ctx.relpath, line = line, start_line = start_line })

  capture.open({
    title = title,
    body = existing and existing.body or '',
    on_save = function(body)
      local fresh = store.read(ctx.file)
      store.upsert(fresh, { path = ctx.relpath, line = line, start_line = start_line, body = body })
      store.write(ctx.file, fresh)
      if vim.api.nvim_buf_is_valid(bufnr) then render_buf(bufnr, ctx) end
    end,
  })
end

function M.quickfix()
  local ctx, err = M.context()
  if not ctx then return notify_err(err) end
  local doc = store.read(ctx.file)
  render.quickfix(ctx.root, doc.entries, M.load_threads(ctx))
  vim.cmd('copen')
end

function M.open_file()
  local ctx, err = M.context()
  if not ctx then return notify_err(err) end
  vim.fn.mkdir(vim.fn.fnamemodify(ctx.file, ':h'), 'p')
  vim.cmd('edit ' .. vim.fn.fnameescape(ctx.file))
end

function M.setup()
  vim.api.nvim_create_user_command('ReviewComment', M.comment, { range = true, desc = 'Review: comment at cursor/selection' })
  vim.api.nvim_create_user_command('ReviewRender', M.render_current, { desc = 'Review: re-render comments in buffer' })
  vim.api.nvim_create_user_command('ReviewQuickfix', M.quickfix, { desc = 'Review: comments → quickfix' })
  vim.api.nvim_create_user_command('ReviewOpen', M.open_file, { desc = 'Review: open pending comments file' })
  vim.api.nvim_create_user_command('ReviewPush', function(o) require('mpataki.review.sync').push(o.bang) end,
    { bang = true, desc = 'Review: push pending comments as a draft GitHub review' })
  vim.api.nvim_create_user_command('ReviewPull', function() require('mpataki.review.sync').pull() end,
    { desc = 'Review: pull remote threads + my pending review' })

  vim.keymap.set('n', '<leader>gc', M.comment, { desc = 'Review comment at cursor' })
  vim.keymap.set('x', '<leader>gc', ':ReviewComment<CR>', { silent = true, desc = 'Review comment on selection' })
  vim.keymap.set('n', '<leader>gC', M.quickfix, { desc = 'Review comments → quickfix' })

  local group = vim.api.nvim_create_augroup('MpatakiReview', { clear = true })
  vim.api.nvim_create_autocmd('BufWinEnter', {
    group = group,
    callback = function(ev)
      if vim.bo[ev.buf].buftype ~= '' then return end
      local ctx = M.context(ev.buf)
      if not ctx or vim.fn.filereadable(ctx.file) ~= 1 and vim.fn.filereadable(ctx.remote_file) ~= 1 then return end
      render_buf(ev.buf, ctx)
    end,
  })
end

return M
```

Note the `BufWinEnter` hook calls `pr.info`, which shells to `gh pr view` once per repo root per session (cached). For non-PR branches the cache still holds a result, so repeated entries cost one `git rev-parse` each.

For Task 7 the probe's `:ReviewPush` / `:ReviewPull` existence checks need the commands registered; `sync.lua` does not exist yet, so the commands are registered but calling them would error until Task 7. That is expected within this task.

- [ ] **Step 5: Wire into `nvim/lua/mpataki/init.lua`**

Append after `require("mpataki.nvim_goto")`:

```lua
require("mpataki.review").setup()
```

- [ ] **Step 6: Run the probe, expect all PASS**

Run: `cd ~/dotfiles/nvim && nvim --headless -c 'luafile probes/review/capture_probe.lua' -c 'qa'; echo "exit=$?"`
Expected: all `PASS`, `exit=0`.

- [ ] **Step 7: Load gate for the full config**

Run: `cd ~/dotfiles/nvim && nvim --headless -c 'lua print("loaded")' -c 'qa' 2>&1 | tail -3`
Expected: `loaded`, no error lines.

- [ ] **Step 8: Commit**

```bash
cd ~/dotfiles && git add nvim/lua/mpataki/review/capture.lua nvim/lua/mpataki/review/init.lua nvim/lua/mpataki/init.lua nvim/probes/review/capture_probe.lua
git commit -m "feat(nvim): ReviewComment float captures PR comments at the cursor"
```

---

### Task 7: `sync.lua` — push with guards, pull

**Files:**
- Create: `nvim/lua/mpataki/review/sync.lua`
- Test: `nvim/probes/review/sync_probe.lua`

**Interfaces:**
- Consumes: `pr.*`, `store.*`, `gh.*`, `review.context`, `review.load_threads`, `render.render`.
- Produces:
  - `sync.check_push(ctx, doc, pending, head) -> ok, err` — pure guard evaluation: `head ~= ctx.info.head` → err; `#doc.entries == 0` → err; entry outside `pr.diff_ranges` → err naming `store.key(entry)`; `pending` present and `store.fingerprint(pending.comments) ~= doc.header.pushed` → err containing `'clobber'`.
  - `sync.push(bang)` — `:ReviewPush[!]`. `bang` skips only the clobber guard.
  - `sync.pull()` — `:ReviewPull`.

- [ ] **Step 1: Write the failing probe**

`nvim/probes/review/sync_probe.lua`:

```lua
package.path = vim.fn.expand('~/dotfiles/nvim/probes/review/?.lua') .. ';' .. package.path
local P = require('probe')
local F = require('fixture')
local pr = require('mpataki.review.pr')
local store = require('mpataki.review.store')
local gh = require('mpataki.review.gh')
local review = require('mpataki.review')
local sync = require('mpataki.review.sync')

local notes = {}
vim.notify = function(msg) table.insert(notes, msg) end
local function last_note() return notes[#notes] or '' end

local fx = F.repo()
pr.clear_cache()
local info = pr.info(fx.root)
info.number = 7; info.head = fx.head_sha; info.url = 'https://example.invalid/pr/7'

vim.cmd('edit ' .. vim.fn.fnameescape(fx.root .. '/sub/dir/file.txt'))
local ctx = assert(review.context())

-- Fake gh: records calls, serves canned responses keyed by substring.
local calls, canned = {}, {}
gh.runner = function(argv, opts)
  table.insert(calls, { argv = argv, opts = opts })
  local key = table.concat(argv, ' ')
  local best, best_len = nil, -1
  for pat, resp in pairs(canned) do -- longest matching pattern wins
    if key:find(pat, 1, true) and #pat > best_len then best, best_len = resp, #pat end
  end
  if best then return best end
  return { code = 1, stdout = '', stderr = 'no canned: ' .. key }
end
local function json(t) return { code = 0, stdout = vim.json.encode(t), stderr = '' } end
canned['user'] = json({ login = 'mpataki' })
canned['pulls/7/reviews'] = json({ {} })          -- no pending review
canned['POST repos/{owner}/{repo}/pulls/7/reviews'] = json({ id = 501 })
canned['DELETE repos/{owner}/{repo}/pulls/7/reviews/501'] = { code = 0, stdout = '', stderr = '' }
canned['pulls/7/comments'] = json({ { { id = 9, path = 'sub/dir/file.txt', line = 11, side = 'RIGHT',
  body = 'remote says hi', user = { login = 'bob' }, html_url = 'u', pull_request_review_id = 3 } } })

-- Pure guard checks -----------------------------------------------------------
local doc = { header = {}, entries = {} }
local ok, err = sync.check_push(ctx, doc, nil, fx.head_sha)
P.ok(not ok and err:find('no pending comments', 1, true), 'empty doc refused')

store.upsert(doc, { path = 'sub/dir/file.txt', line = 5, body = 'c1' })
ok, err = sync.check_push(ctx, doc, nil, 'othersha')
P.ok(not ok and err:find('HEAD', 1, true), 'head mismatch refused: ' .. tostring(err))

store.upsert(doc, { path = 'sub/dir/file.txt', line = 1, body = 'outside' })
ok, err = sync.check_push(ctx, doc, nil, fx.head_sha)
P.ok(not ok and err:find('sub/dir/file.txt:1', 1, true), 'out-of-diff entry named: ' .. tostring(err))
store.remove(doc, 'sub/dir/file.txt', 1)

local pending = { id = 55, comments = { { path = 'sub/dir/file.txt', line = 5, body = 'edited in browser' } } }
doc.header.pushed = store.fingerprint(doc.entries)
ok, err = sync.check_push(ctx, doc, pending, fx.head_sha)
P.ok(not ok and err:find('clobber', 1, true), 'server drift refused: ' .. tostring(err))

pending.comments[1].body = 'c1'
ok, err = sync.check_push(ctx, doc, pending, fx.head_sha)
P.ok(ok, 'matching server fingerprint passes: ' .. tostring(err))

-- Push end-to-end against the fake -------------------------------------------
store.write(ctx.file, doc)
calls = {}
sync.push(false)
P.wait(200)
local posted
for _, c in ipairs(calls) do
  if vim.tbl_contains(c.argv, 'POST') then posted = vim.json.decode(c.opts.stdin) end
end
P.ok(posted ~= nil, 'POST sent')
P.eq(posted and posted.commit_id, fx.head_sha, 'commit_id is PR head')
P.eq(posted and #posted.comments, 1, 'one comment posted')
local after = store.read(ctx.file)
P.eq(after.header.pushed, store.fingerprint(after.entries), 'header pushed updated')
P.eq(after.header.head, fx.head_sha, 'header head updated')
P.ok(last_note():find('example.invalid/pr/7', 1, true) ~= nil, 'PR URL printed')

-- Second push with a server pending review that matches: DELETE then POST.
canned['pulls/7/reviews'] = json({ { { id = 501, state = 'PENDING', user = { login = 'mpataki' } } } })
canned['pulls/7/reviews/501/comments'] = json({ { { path = 'sub/dir/file.txt', line = 5, start_line = vim.NIL, body = 'c1' } } })
calls = {}
sync.push(false)
P.wait(200)
local order = {}
for _, c in ipairs(calls) do
  if vim.tbl_contains(c.argv, 'DELETE') then table.insert(order, 'DELETE') end
  if vim.tbl_contains(c.argv, 'POST') then table.insert(order, 'POST') end
end
P.eq(table.concat(order, ','), 'DELETE,POST', 'replace = delete then create')

-- Drift on server + no bang: refused, no DELETE. With bang: proceeds.
canned['pulls/7/reviews/501/comments'] = json({ { { path = 'sub/dir/file.txt', line = 5, start_line = vim.NIL, body = 'browser edit' } } })
calls = {}
sync.push(false)
P.wait(200)
P.ok(last_note():find('clobber', 1, true) ~= nil, 'drift refused without bang')
local deleted = false
for _, c in ipairs(calls) do if vim.tbl_contains(c.argv, 'DELETE') then deleted = true end end
P.ok(not deleted, 'no DELETE on refusal')
calls = {}
sync.push(true)
P.wait(200)
deleted = false
for _, c in ipairs(calls) do if vim.tbl_contains(c.argv, 'DELETE') then deleted = true end end
P.ok(deleted, 'bang overrides drift guard')

-- Pull: remote threads cached, pending section replaced from server ---------
canned['pulls/7/reviews/501/comments'] = json({ { { path = 'sub/dir/file.txt', line = 5, start_line = vim.NIL, body = 'from server' } } })
sync.pull()
P.wait(200)
local threads = review.load_threads(ctx)
P.eq(#threads, 1, 'remote thread cached')
P.eq(threads[1].author, 'bob', 'thread author cached')
local pulled = store.read(ctx.file)
P.eq(pulled.entries[1].body, 'from server', 'pending section replaced from server')
P.eq(pulled.header.pushed, store.fingerprint(pulled.entries), 'pull sets pushed fingerprint to server state')
P.eq(#vim.api.nvim_buf_get_extmarks(0, require('mpataki.review.render').ns, 0, -1, {}), 2, 'pull re-rendered pending + remote')

P.done()
```

- [ ] **Step 2: Run it, expect failure**

Run: `cd ~/dotfiles/nvim && nvim --headless -c 'luafile probes/review/sync_probe.lua' -c 'qa'; echo "exit=$?"`
Expected: `module 'mpataki.review.sync' not found`.

- [ ] **Step 3: Implement `sync.lua`**

```lua
-- Push the local pending-comments file into a GitHub *pending* review (never
-- submitted from here), and pull remote threads + my pending review back.
-- Both directions are explicit overwrites; check_push stops a push that would
-- silently discard edits made to the pending review in the browser.
local pr = require('mpataki.review.pr')
local store = require('mpataki.review.store')
local gh = require('mpataki.review.gh')
local render = require('mpataki.review.render')
local review = require('mpataki.review')

local M = {}

local function notify(msg, level)
  vim.notify('review: ' .. msg, level or vim.log.levels.INFO)
end

local function local_head(root)
  local r = pr.git(root, { 'rev-parse', 'HEAD' })
  return vim.trim(r.stdout)
end

function M.check_push(ctx, doc, pending, head)
  if #doc.entries == 0 then
    return false, 'no pending comments in ' .. ctx.file
  end
  if head ~= ctx.info.head then
    return false, ('local HEAD %s ≠ PR head %s; push or pull the branch first'):format(head:sub(1, 8), (ctx.info.head or '?'):sub(1, 8))
  end
  local ranges = {}
  for _, e in ipairs(doc.entries) do
    ranges[e.path] = ranges[e.path] or pr.diff_ranges(ctx.root, ctx.info.base_sha, ctx.info.head, e.path)
    local r = ranges[e.path]
    if not pr.in_ranges(r, e.line) or (e.start_line and not pr.in_ranges(r, e.start_line)) then
      return false, ('%s is outside the PR diff; GitHub would reject the whole batch'):format(store.key(e))
    end
  end
  if pending and store.fingerprint(pending.comments) ~= doc.header.pushed then
    return false, 'pending review on GitHub differs from what was last pushed; :ReviewPull to take theirs, or :ReviewPush! to clobber'
  end
  return true, nil
end

local function rerender(ctx)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local bctx = review.context(buf)
    if bctx and bctx.file == ctx.file then
      local doc = store.read(ctx.file)
      render.render(buf, bctx.relpath, doc.entries, review.load_threads(ctx))
    end
  end
end

function M.push(bang)
  local ctx, err = review.context()
  if not ctx then return notify(err, vim.log.levels.ERROR) end
  local doc = store.read(ctx.file)

  local login, lerr = gh.login(ctx.root)
  if not login then return notify(lerr, vim.log.levels.ERROR) end
  local pending, perr = gh.pending_review(ctx.root, ctx.info.number, login)
  if perr then return notify(perr, vim.log.levels.ERROR) end

  local ok, cerr = M.check_push(ctx, doc, (not bang) and pending or nil, local_head(ctx.root))
  if not ok then return notify(cerr, vim.log.levels.ERROR) end

  if pending then
    local dok, derr = gh.delete_review(ctx.root, ctx.info.number, pending.id)
    if not dok then return notify(derr, vim.log.levels.ERROR) end
  end
  local id, cerr2 = gh.create_pending(ctx.root, ctx.info.number, ctx.info.head, doc.entries)
  if not id then return notify(cerr2, vim.log.levels.ERROR) end

  local repo = ctx.info.url and ctx.info.url:match('github%.com/([^/]+/[^/]+)/pull')
  doc.header.repo = (repo or '?') .. '#' .. ctx.info.number
  doc.header.head = ctx.info.head
  doc.header.pushed = store.fingerprint(doc.entries)
  store.write(ctx.file, doc)

  notify(('pushed %d comment(s) as pending review %d — %s'):format(#doc.entries, id, ctx.info.url or ''))
end

function M.pull()
  local ctx, err = review.context()
  if not ctx then return notify(err, vim.log.levels.ERROR) end

  local login, lerr = gh.login(ctx.root)
  if not login then return notify(lerr, vim.log.levels.ERROR) end
  local pending, perr = gh.pending_review(ctx.root, ctx.info.number, login)
  if perr then return notify(perr, vim.log.levels.ERROR) end

  local threads, terr = gh.threads(ctx.root, ctx.info.number)
  if not threads then return notify(terr, vim.log.levels.ERROR) end
  if pending then
    threads = vim.tbl_filter(function(t) return t.review_id ~= pending.id end, threads)
  end
  vim.fn.mkdir(vim.fn.fnamemodify(ctx.remote_file, ':h'), 'p')
  vim.fn.writefile({ vim.json.encode(threads) }, ctx.remote_file)

  local doc = store.read(ctx.file)
  doc.entries = pending and pending.comments or {}
  doc.header.head = ctx.info.head
  doc.header.pushed = store.fingerprint(doc.entries)
  store.write(ctx.file, doc)

  rerender(ctx)
  notify(('pulled %d thread(s), %d pending comment(s)'):format(#threads, #doc.entries))
end

return M
```

- [ ] **Step 4: Run the probe, expect all PASS**

Run: `cd ~/dotfiles/nvim && nvim --headless -c 'luafile probes/review/sync_probe.lua' -c 'qa'; echo "exit=$?"`
Expected: all `PASS`, `exit=0`.

- [ ] **Step 5: Run every review probe**

Run:
```bash
cd ~/dotfiles/nvim && for p in probes/review/*_probe.lua; do echo "== $p"; nvim --headless -c "luafile $p" -c 'qa' 2>&1 | tail -1; done
```
Expected: each ends with `probe: N passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
cd ~/dotfiles && git add nvim/lua/mpataki/review/sync.lua nvim/probes/review/sync_probe.lua
git commit -m "feat(nvim): ReviewPush/ReviewPull sync the pending review with GitHub"
```

---

### Task 8: which-key labels, probe runner script, and docs

**Files:**
- Modify: `nvim/lua/mpataki/plugins/which-key.lua` (add `<leader>g` group entries if the file registers groups; inspect first)
- Create: `nvim/probes/review/run.sh`
- Modify: `nvim/README.md` if it exists, else `docs/superpowers/specs/2026-09-22-nvim-pr-review-comments-design.md` gets a short "Usage" section at the end.

- [ ] **Step 1: Runner script**

`nvim/probes/review/run.sh`:

```bash
#!/usr/bin/env bash
# Runs every review probe headless; exits non-zero if any fails.
set -u
cd "$(dirname "$0")/../.." || exit 1
fail=0
for p in probes/review/*_probe.lua; do
  echo "== $p"
  if ! nvim --headless -c "luafile $p" -c 'qa' 2>&1 | tail -1 | grep -q ', 0 failed'; then
    fail=1
  fi
done
exit $fail
```

`chmod +x nvim/probes/review/run.sh`. Run it; expect exit 0.

- [ ] **Step 2: which-key**

Open `nvim/lua/mpataki/plugins/which-key.lua`. If it has a `spec`/`add` list of `<leader>g` entries, add `{ '<leader>gc', desc = 'Review comment' }` and `{ '<leader>gC', desc = 'Review quickfix' }` alongside. If it only sets groups, add nothing (the keymap `desc` already shows).

- [ ] **Step 3: Usage section**

Append to the spec file:

```markdown
## Usage

1. `gh pr checkout N` (or a worktree on the PR branch), open nvim there.
2. `<leader>gS` picks a PR file; `<leader>go` for overlay.
3. `<leader>gc` on a changed line (or a visual range) opens the float. `:w` saves, `q` cancels. Empty body deletes.
4. `:ReviewPull` fetches everyone's threads and your pending review; comments render as virtual lines, `<leader>gC` lists them in quickfix.
5. `:ReviewPush` creates/replaces your pending review on GitHub. Finish in the browser.
6. Escape hatch: `:ReviewOpen` edits `<git-common-dir>/reviews/<N>.md` directly.
```

- [ ] **Step 4: Commit**

```bash
cd ~/dotfiles && git add nvim/probes/review/run.sh nvim/lua/mpataki/plugins/which-key.lua docs/superpowers/specs/2026-09-22-nvim-pr-review-comments-design.md
git commit -m "chore(nvim): review probe runner, which-key labels, usage notes"
```

---

### Task 9: Real-PR smoke test (coordinator runs this, not a subagent)

- [ ] Pick an open PR authored by Mat (`gh search prs --author=@me --state=open`), check it out in a temp worktree.
- [ ] In nvim there: `:ReviewPull` (expect thread count), `<leader>gc` on a changed line, `:ReviewPush` (expect pending review URL). Verify on GitHub via `gh api repos/{owner}/{repo}/pulls/N/reviews --jq '.[] | select(.state=="PENDING") | .id'`.
- [ ] `:ReviewPush` again without changes: expect DELETE+POST, same content.
- [ ] Delete the pending review: `gh api -X DELETE repos/{owner}/{repo}/pulls/N/reviews/<id>`. Remove the worktree and the `reviews/N.*` files in that repo's common dir.
- [ ] Record outcome in the wrap-up.
