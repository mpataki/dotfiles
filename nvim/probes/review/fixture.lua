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
  sh({ 'git', '-c', 'commit.gpgsign=false', 'commit', '-q', '-m', 'base' }, root)
  local base_sha = sh({ 'git', 'rev-parse', 'HEAD' }, root)

  sh({ 'git', 'checkout', '-q', '-b', 'feature' }, root)
  lines[5] = 'line 5 changed'
  lines[11] = 'line 11'
  vim.fn.writefile(lines, root .. '/sub/dir/file.txt')
  sh({ 'git', '-c', 'commit.gpgsign=false', 'commit', '-q', '-am', 'change' }, root)
  local head_sha = sh({ 'git', 'rev-parse', 'HEAD' }, root)

  return { root = root, base_sha = base_sha, head_sha = head_sha }
end

-- Installs a fake `gh.runner` so probes never shell out to the real `gh`.
-- Returns (calls, canned): `calls` records every { argv, opts } in order; fill
-- `canned` with pattern -> response, a { code, stdout, stderr } table or a
-- function(argv, opts) returning one. Longest matching pattern wins, so
-- 'pulls/7/reviews/55/comments' beats 'pulls/7/reviews', and
-- 'POST repos/.../pulls/7/reviews' beats both.
function F.fake_gh(gh)
  local calls, canned = {}, {}
  gh.runner = function(argv, opts)
    table.insert(calls, { argv = argv, opts = opts })
    local key = table.concat(argv, ' ')
    local best, best_len = nil, -1
    for pat, resp in pairs(canned) do
      if key:find(pat, 1, true) and #pat > best_len then best, best_len = resp, #pat end
    end
    if best == nil then
      return { code = 1, stdout = '', stderr = 'no canned response for: ' .. key }
    end
    if type(best) == 'function' then return best(argv, opts) end
    return best
  end
  return calls, canned
end

return F
