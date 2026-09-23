-- GitHub access for the review flow, all through `gh api`. The runner is
-- injectable so probes substitute a fake; nothing here is exercised against
-- GitHub in tests. `{owner}/{repo}` placeholders resolve from the cwd's remote,
-- which is why every call runs with cwd = repo root.
local M = {}

-- env: forced color (CLICOLOR_FORCE, set in agent sessions) makes gh emit
-- ANSI-wrapped JSON that vim.json.decode rejects; merged over the inherited
-- environment, never clear_env, so gh keeps PATH, HOME and its token.
function M.runner(argv, opts)
  local r = vim.system(argv, {
    cwd = opts.cwd,
    stdin = opts.stdin,
    text = true,
    env = { CLICOLOR_FORCE = '0', NO_COLOR = '1' },
  }):wait()
  return { code = r.code, stdout = r.stdout or '', stderr = r.stderr or '' }
end

local function first_line(s)
  return (vim.trim(s or ''):match('^[^\n]*'))
end

-- JSON null decodes to vim.NIL, a *userdata* — truthy, and it throws when
-- indexed. Every value read off a decoded payload goes through this, or a null
-- field sails past an `or` default and blows up somewhere far away.
local function nilify(v)
  if v == vim.NIL then return nil end
  return v
end

-- `args` may lead with flags ('-X', 'POST'), so the endpoint is the first
-- argument that is neither a flag nor a flag's value: an error blaming '-X'
-- names no call anyone can go look at.
local function endpoint_of(args)
  local skip = false
  for _, a in ipairs(args) do
    if skip then
      skip = false
    elseif a == '-X' or a == '--method' or a == '-H' or a == '--header' then
      skip = true
    elseif a:sub(1, 1) ~= '-' then
      return a
    end
  end
  return args[1] or ''
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
    return nil, ('gh api %s: %s'):format(endpoint_of(args), first_line(r.stderr))
  end
  if vim.trim(r.stdout) == '' then return {}, nil end
  local ok, data = pcall(vim.json.decode, r.stdout)
  if not ok then return nil, 'gh api: bad JSON: ' .. first_line(r.stdout) end
  if opts.paginate then
    -- --slurp wraps every page in an outer array. A list endpoint's pages are
    -- arrays to splice; an object endpoint yields one object per page, which has
    -- to be kept whole — list_extend over a map appends nothing (its # is 0),
    -- which would answer "empty" for a perfectly good response.
    if not vim.islist(data) then return { data }, nil end
    local flat = {}
    for _, page in ipairs(data) do
      if vim.islist(page) then
        vim.list_extend(flat, page)
      else
        table.insert(flat, page)
      end
    end
    return flat, nil
  end
  return data, nil
end

function M.login(root)
  local data, err = M.api(root, { 'user' })
  if not data then return nil, err end
  local login = nilify(data.login)
  -- A login-less success would silently match no pending review, and sync would
  -- open a second one over the live one. Fail loudly instead.
  if not login then return nil, 'gh api user: no login in response' end
  return login, nil
end

local function endpoint(number, suffix)
  return ('repos/{owner}/{repo}/pulls/%d%s'):format(number, suffix or '')
end

function M.threads(root, number)
  local data, err = M.api(root, { endpoint(number, '/comments') }, { paginate = true })
  if not data then return nil, err end
  local out = {}
  for _, c in ipairs(data) do
    local user = nilify(c.user)
    table.insert(out, {
      id = nilify(c.id),
      path = nilify(c.path),
      line = nilify(c.line) or nilify(c.original_line),
      start_line = nilify(c.start_line) or nilify(c.original_start_line),
      side = nilify(c.side) or 'RIGHT',
      body = nilify(c.body) or '',
      author = user and nilify(user.login) or '?',
      html_url = nilify(c.html_url),
      in_reply_to_id = nilify(c.in_reply_to_id),
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
    local user = nilify(r.user)
    if r.state == 'PENDING' and user and nilify(user.login) == login then mine = r end
  end
  if not mine then return nil, nil end
  -- An id-less pending review can be neither fetched nor deleted; reporting
  -- "none" would have sync create a second review alongside the live one.
  local mine_id = nilify(mine.id)
  if not mine_id then
    return nil, ('gh api %s: pending review has no id'):format(endpoint(number, '/reviews'))
  end

  local comments, cerr = M.api(root, { endpoint(number, '/reviews/' .. mine_id .. '/comments') }, { paginate = true })
  if not comments then return nil, cerr end
  local entries = {}
  for _, c in ipairs(comments) do
    table.insert(entries, {
      path = nilify(c.path),
      -- GitHub nulls `line` and `start_line` together once a comment goes
      -- outdated; without both fallbacks a range comes back as a single line,
      -- and this shape round-trips back to the server.
      line = nilify(c.line) or nilify(c.original_line),
      start_line = nilify(c.start_line) or nilify(c.original_start_line),
      body = nilify(c.body) or '',
    })
  end
  return { id = mine_id, comments = entries }, nil
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
  -- The review may well exist server-side by now, so an id we cannot read is an
  -- error: returning nil with no error reads as "nothing happened" and sends
  -- sync back to create a second one.
  local id = nilify(data.id)
  if not id then
    return nil, ('gh api %s: no review id in response'):format(endpoint(number, '/reviews'))
  end
  return id, nil
end

return M
