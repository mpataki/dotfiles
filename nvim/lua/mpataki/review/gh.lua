-- GitHub access for the review flow, all through `gh api`. The runner is
-- injectable so probes substitute a fake; nothing here is exercised against
-- GitHub in tests. `{owner}/{repo}` placeholders resolve from the cwd's remote,
-- which is why every call runs with cwd = repo root.
local M = {}

-- env: forced color (CLICOLOR_FORCE, set in agent sessions) makes gh emit
-- ANSI-wrapped JSON that vim.json.decode rejects; merged over the inherited
-- environment, never clear_env, so gh keeps PATH, HOME and its token.
-- :wait() with no argument waits forever: a gh call that hangs (an unreachable
-- host, a credential prompt) would freeze the editor with no way back. Every
-- call here is synchronous, so the bound is the only way out.
M.timeout_ms = 15000

function M.runner(argv, opts)
  local r = vim.system(argv, {
    cwd = opts.cwd,
    stdin = opts.stdin,
    text = true,
    env = { CLICOLOR_FORCE = '0', NO_COLOR = '1' },
  }):wait(M.timeout_ms)
  local function timed_out(stderr)
    return vim.trim(('%s timed out after %gs\n%s'):format(argv[1], M.timeout_ms / 1000, stderr or ''))
  end
  -- :wait hands back nothing at all when the kill leaves the pipes open behind
  -- it (a child that outlives its parent holds them), so a nil result is a
  -- timeout too — and indexing it is how this crashes instead.
  if not r then
    return { code = 124, stdout = '', stderr = timed_out() }
  end
  local stderr = r.stderr or ''
  -- A timed-out process is killed: it exits on a signal with an empty stderr,
  -- and 'gh api user: ' with nothing after it explains nothing.
  if r.code ~= 0 and (r.signal or 0) ~= 0 then
    stderr = timed_out(stderr)
  end
  return { code = r.code, stdout = r.stdout or '', stderr = stderr }
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

-- REST is useless for a *pending* review's comments: GET
-- .../reviews/{id}/comments answers line, original_line, start_line,
-- original_start_line and side all null for one, leaving only `position`, which
-- is a diff offset and not what this file anchors on. GraphQL returns the lines.
local function pending_comments_query(node_id, after)
  local cursor = after and ('"' .. after .. '"') or 'null'
  return ('{ node(id: "%s") { ... on PullRequestReview { state comments(first: 100, after: %s)'
    .. ' { pageInfo { hasNextPage endCursor } nodes { path line startLine originalLine'
    .. ' originalStartLine body } } } } }'):format(node_id, cursor)
end

-- `data` and `node` are both nullable in a GraphQL envelope, and vim.NIL is
-- truthy: indexing one throws far from here.
local function review_node(payload)
  local data = nilify(payload and payload.data)
  if not data then return nil end
  return nilify(data.node)
end

local function pending_comments(root, node_id)
  local entries, after = {}, nil
  while true do
    local payload, err = M.api(root, { 'graphql', '-f', 'query=' .. pending_comments_query(node_id, after) })
    if not payload then return nil, err end
    local node = review_node(payload)
    if not node then return nil, 'gh api graphql: no pending review node in response' end
    local comments = nilify(node.comments) or {}
    for _, c in ipairs(nilify(comments.nodes) or {}) do
      table.insert(entries, {
        path = nilify(c.path),
        -- GitHub nulls `line` and `startLine` together once a comment goes
        -- outdated; without both fallbacks a range comes back as a single line,
        -- and this shape round-trips back to the server.
        line = nilify(c.line) or nilify(c.originalLine),
        start_line = nilify(c.startLine) or nilify(c.originalStartLine),
        body = nilify(c.body) or '',
      })
    end
    local page = nilify(comments.pageInfo) or {}
    if not nilify(page.hasNextPage) then return entries, nil end
    -- hasNextPage with no cursor would re-request page 1 forever.
    after = nilify(page.endCursor)
    if not after then return entries, nil end
  end
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
  -- "none" would have sync create a second review alongside the live one. The
  -- node id is just as load-bearing: without it the comments cannot be read.
  local mine_id = nilify(mine.id)
  if not mine_id then
    return nil, ('gh api %s: pending review has no id'):format(endpoint(number, '/reviews'))
  end
  local node_id = nilify(mine.node_id)
  if not node_id then
    return nil, ('gh api %s: pending review has no node_id'):format(endpoint(number, '/reviews'))
  end

  local entries, cerr = pending_comments(root, node_id)
  if not entries then return nil, cerr end
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
