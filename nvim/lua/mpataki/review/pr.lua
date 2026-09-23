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
  return (vim.fn.fnamemodify(d, ':p'):gsub('/$', ''))
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

local function gh_pr_view(root)
  local r = run({ 'gh', 'pr', 'view', '--json', 'number,baseRefName,headRefOid,url' }, root)
  if r.code ~= 0 then return nil end
  local ok, data = pcall(vim.json.decode, r.stdout)
  if not ok then return nil end
  return data
end

function M.info(root, opts)
  if not root or root == '' then return nil, 'no repo root' end
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
