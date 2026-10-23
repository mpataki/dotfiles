-- Review identity. Single source of: repo root, repo-relative paths, the
-- branch (what a draft is keyed on), the optional PR number/base/head (via gh),
-- merge-base, and diff line ranges. A review needs a branch, not a PR.
-- Every path handed to git or GitHub goes through relpath(); nvim's cwd is
-- never consulted, because it is often a different directory or repo.
local M = {}

-- root..'\0'..branch -> { info = info } | { err = err }. Keyed by branch too:
-- the PR (and so the base) belongs to the branch, and a checkout mid-session
-- must not answer with the old branch's PR. Failures are cached too: the passive
-- BufWinEnter render would otherwise re-run `gh pr view` (network) plus two
-- merge-base attempts on every window entry in a repo with no merge base.
-- `refresh` and clear_cache() drop both kinds, so a cached failure never
-- outlives the next explicit gesture.
local cache = {}

-- root -> git common dir. A root's common dir cannot change while nvim runs,
-- and this is on the BufWinEnter path: one `git rev-parse` per window entry,
-- per file, forever, for an answer that is always the same string.
local common_dirs = {}

-- root -> this worktree's git dir (not the common one: HEAD is per worktree).
-- Constant per root, like common_dirs; what it holds (HEAD) is not, and is read
-- fresh.
local git_dirs = {}

-- vim.system():wait() with no argument waits forever: a git or gh call that
-- hangs (a credential prompt, an unreachable host) would freeze the editor with
-- no way back. Bounded instead, and the kill reports itself as a timeout.
M.timeouts = { git = 10000, gh = 15000 }

-- Forced color breaks every parser downstream, so the runner neutralizes it for
-- both git and gh: CLICOLOR_FORCE in the environment (agent sessions set it;
-- f8ccc2b dropped it from the shell for exactly this reason) makes `gh --json`
-- emit ANSI-wrapped JSON that vim.json.decode rejects, and a user's
-- `color.ui=always` colors the `@@` headers past parse_hunk_ranges' '^@@'.
-- No clear_env: vim.system merges this over the inherited environment, which
-- gh still needs for PATH, HOME and its token.
local function timed_out(argv, timeout, stderr)
  return vim.trim(('%s timed out after %gs\n%s'):format(argv[1], timeout / 1000, stderr or ''))
end

local function run(argv, cwd, timeout)
  timeout = timeout or M.timeouts.git
  local r = vim.system(argv, {
    cwd = cwd,
    text = true,
    env = { CLICOLOR_FORCE = '0', NO_COLOR = '1' },
  }):wait(timeout)
  -- :wait hands back nothing at all when the kill leaves the pipes open behind
  -- it (a git alias that shells out keeps stdout in a grandchild), so a nil
  -- result is a timeout too — and indexing it is how this crashes instead.
  if not r then
    return { code = 124, stdout = '', stderr = timed_out(argv, timeout) }
  end
  local stderr = r.stderr or ''
  -- A timed-out process is killed, so it exits on a signal with nothing on
  -- stderr: without this the caller reports an empty reason for the failure.
  if r.code ~= 0 and (r.signal or 0) ~= 0 then
    stderr = timed_out(argv, timeout, stderr)
  end
  return { code = r.code, stdout = r.stdout or '', stderr = stderr }
end

local function first_line(s)
  return (vim.trim(s or ''):match('^[^\n]*'))
end

function M.git(root, argv)
  return run(vim.list_extend({ 'git' }, argv), root)
end

-- Returns nil when the name is not a real on-disk path. Scheme buffers
-- ('diffview:///panels/1', 'term://…', 'oil://…') name no directory, and
-- vim.system *throws* ENOENT on a cwd that does not exist rather than failing
-- the command — so callers would never see a nil to fall back from.
local function dir_of(abs_path)
  if vim.fn.isdirectory(abs_path) == 1 then return abs_path end
  local dir = vim.fn.fnamemodify(abs_path, ':h')
  if vim.fn.isdirectory(dir) == 0 then return nil end
  return dir
end

function M.root(abs_path)
  if not abs_path or abs_path == '' then return nil end
  local dir = dir_of(abs_path)
  if not dir then return nil end
  local r = run({ 'git', 'rev-parse', '--show-toplevel' }, dir)
  if r.code ~= 0 then return nil end
  return vim.trim(r.stdout)
end

-- The repo a user gesture acts on: the current buffer's file, else nvim's cwd.
function M.current_root()
  return M.root(vim.api.nvim_buf_get_name(0)) or M.root(vim.fn.getcwd())
end

function M.common_dir(root)
  if common_dirs[root] then return common_dirs[root] end
  local r = M.git(root, { 'rev-parse', '--git-common-dir' })
  local d = vim.trim(r.stdout)
  if d:sub(1, 1) ~= '/' then d = root .. '/' .. d end
  local common = (vim.fn.fnamemodify(d, ':p'):gsub('/$', ''))
  common_dirs[root] = common
  return common
end

-- Path relative to `root`, forward slashes. Returns nil when `abs_path` is not
-- inside `root` — a path from another repo has no repo-relative name here, and
-- silently returning a truncated one would address a comment at the wrong file.
function M.relpath(root, abs_path)
  if not root or root == '' or not abs_path or abs_path == '' then return nil end
  local full = vim.uv.fs_realpath(abs_path) or vim.fn.fnamemodify(abs_path, ':p')
  if full:sub(1, #root + 1) ~= root .. '/' then return nil end
  local rel = full:sub(#root + 2)
  return (rel:gsub('\\', '/'))
end

local function merge_base(root, ref)
  local r = M.git(root, { 'merge-base', 'HEAD', ref })
  if r.code ~= 0 then return nil end
  return vim.trim(r.stdout)
end

-- nil, reason. The reason matters: unauthenticated, offline, rate-limited and
-- "this branch has no PR" all land here, and a caller that reports them all as
-- "no PR" sends the user looking in the wrong place.
local function gh_pr_view(root)
  local r = run({ 'gh', 'pr', 'view', '--json', 'number,baseRefName,headRefOid,url' }, root, M.timeouts.gh)
  if r.code ~= 0 then
    return nil, first_line(r.stderr) ~= '' and first_line(r.stderr) or 'gh pr view failed'
  end
  local ok, data = pcall(vim.json.decode, r.stdout)
  if not ok then return nil, 'gh pr view: bad JSON' end
  return data, nil
end

-- The checked-out branch, read fresh every call (cheap, local): the draft is
-- keyed on it, and a cached answer would write into the old branch's draft
-- after a checkout.
-- It is on the BufWinEnter path, so it reads <git-dir>/HEAD rather than
-- spawning git per window entry. A reftable repo keeps a placeholder there
-- (refs/heads/.invalid); only then does it ask git.
local DETACHED = 'detached HEAD: check out a branch to review'
function M.branch(root)
  if not git_dirs[root] then
    local r = M.git(root, { 'rev-parse', '--absolute-git-dir' })
    if r.code ~= 0 then return nil, 'not a git repo: ' .. root end
    git_dirs[root] = vim.trim(r.stdout)
  end
  local f = io.open(git_dirs[root] .. '/HEAD', 'r')
  local head = f and vim.trim(f:read('*l') or '') or ''
  if f then f:close() end
  local ref = head:match('^ref: refs/heads/(.+)$')
  if ref and ref ~= '.invalid' then return ref end
  if not ref then return nil, DETACHED end
  local r = M.git(root, { 'symbolic-ref', '--quiet', '--short', 'HEAD' })
  if r.code ~= 0 or vim.trim(r.stdout) == '' then return nil, DETACHED end
  return vim.trim(r.stdout)
end

-- origin/HEAD names the remote's default branch whatever it is called; main
-- and master are the guesses for a repo with no remote HEAD set.
local function default_base(root)
  local r = M.git(root, { 'symbolic-ref', '--quiet', '--short', 'refs/remotes/origin/HEAD' })
  local ref = r.code == 0 and vim.trim(r.stdout) or ''
  return (ref ~= '' and merge_base(root, ref)) or merge_base(root, 'main') or merge_base(root, 'master')
end

function M.info(root, opts)
  if not root or root == '' then return nil, 'no repo root' end
  opts = opts or {}
  -- nil on a detached HEAD: the PR-base pickers and overlay work there, only
  -- a review draft needs a branch (review's repo_context refuses for it).
  local branch, berr = M.branch(root)
  local key = root .. '\0' .. (branch or '')
  local hit = cache[key]
  if not opts.refresh and hit then return hit.info, hit.err end

  local info = { root = root, branch = branch, branch_err = berr, common_dir = M.common_dir(root) }
  local pr, pr_err = gh_pr_view(root)
  info.pr_err = pr_err
  if pr then
    info.number = pr.number
    info.base_ref = pr.baseRefName
    info.head = pr.headRefOid
    info.url = pr.url
    info.base_sha = merge_base(root, 'origin/' .. pr.baseRefName) or merge_base(root, pr.baseRefName)
  end
  info.base_sha = info.base_sha or default_base(root)
  if not info.base_sha then
    local err = 'could not find merge base (no PR, no origin/HEAD, no main/master)'
    cache[key] = { err = err }
    return nil, err
  end

  cache[key] = { info = info }
  return info
end

function M.clear_cache()
  cache = {}
  common_dirs = {}
  git_dirs = {}
end

-- New-file line ranges from `@@ -a,b +c,d @@` headers. Matched per line and
-- anchored at the start: a hunk header appearing inside diff *content* (this
-- repo stores .diff files and briefs full of them) is body text, not a hunk.
function M.parse_hunk_ranges(diff_text)
  local ranges = {}
  for line in diff_text:gmatch('[^\n]+') do
    local c, d = line:match('^@@ %-%d+,?%d* %+(%d+),?(%d*) @@')
    if c then
      local start = tonumber(c)
      local count = d == '' and 1 or tonumber(d)
      if count > 0 then
        table.insert(ranges, { s = start, e = start + count - 1 })
      end
    end
  end
  return ranges
end

-- Ranges for `relpath`, or nil, err (first line of git's stderr) when the diff
-- itself fails — an unfetched PR head must not read as "no hunks", which a
-- caller would report as every line being outside the diff.
function M.diff_ranges(root, base_sha, head_ref, relpath)
  local r = M.git(root, { 'diff', '--no-color', '-U3', base_sha, head_ref, '--', relpath })
  if r.code ~= 0 then return nil, (vim.trim(r.stderr):match('^[^\n]*')) end
  return M.parse_hunk_ranges(r.stdout)
end

function M.in_ranges(ranges, line)
  for _, h in ipairs(ranges) do
    if line >= h.s and line <= h.e then return true end
  end
  return false
end

-- The first line of [start_line, line] that sits in no hunk, or nil when all of
-- them do. Every line of a range must be in a hunk, not just its ends: GitHub
-- rejects a range that bridges two hunks, and the whole batch with it. Checked
-- both when a comment is made and when it is pushed — the file is hand-editable
-- in between.
function M.first_line_outside(ranges, start_line, line)
  for l = start_line or line, line do
    if not M.in_ranges(ranges, l) then return l end
  end
  return nil
end

-- A diff that *failed* is not "no hunks": blaming the comment would send the
-- user editing a file when the fix is to fetch the PR branch.
function M.no_diff_message(relpath, head, err)
  return ('no diff for %s against PR head %s: %s — fetch the PR branch?')
    :format(relpath, (head or '?'):sub(1, 8), err or 'git diff failed')
end

return M
