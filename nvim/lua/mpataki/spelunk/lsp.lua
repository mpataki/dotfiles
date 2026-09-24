-- Spelunk capture: watches LSP navigation and turns it into events for the
-- graph. Owns symbol resolution (position -> enclosing SpelunkSym), request
-- observation, and visit detection. Knows nothing about the graph: whether a
-- sym is already in it is asked through the predicate given to set_known().
--
-- Events (one listener, lsp.on_event):
--   { type = 'expand', from = sym, edge = 'caller'|'callee'|'def'|'impl', children = { sym, ... } }
--   { type = 'visit',  sym = sym }
-- Children are de-duplicated by key (path:line:name) and carry `count`.
--
-- Observation wraps each attached client's `request` field. vim.lsp.buf.* and
-- telescope pass their own handlers (or none, meaning client.handlers /
-- vim.lsp.handlers), so global handler overrides never see their results, and
-- the LspRequest autocmd carries no result. The client instance is the one
-- choke point both go through (vim.lsp.buf_request calls client:request).
local M = {}

-- Visit detection debounce. Probes wait past it, so keep it a named constant.
M.DEBOUNCE_MS = 80

local EDGES = {
  ['textDocument/definition'] = 'def',
  ['textDocument/declaration'] = 'def',
  ['textDocument/typeDefinition'] = 'def',
  ['textDocument/implementation'] = 'impl',
  ['textDocument/references'] = 'caller',
  ['callHierarchy/incomingCalls'] = 'caller',
  ['callHierarchy/outgoingCalls'] = 'callee',
}

local listener
local is_known = function() return false end
local wrapped = setmetatable({}, { __mode = 'k' })
local cache = {}    -- uri -> { stamp, symbols }
local inflight = {} -- uri .. stamp -> { cb, ... }
local last = {}     -- last emitted visit: { buf, key }
local timer

local function emit(ev)
  if not listener then return end
  local ok, err = pcall(listener, ev)
  if not ok then
    vim.schedule(function()
      vim.notify('spelunk: event listener failed: ' .. tostring(err), vim.log.levels.WARN)
    end)
  end
end

local function key(sym)
  return sym.path .. ':' .. sym.line .. ':' .. sym.name
end

local function strip_slash(p)
  return (p:gsub('/+$', ''))
end

local function relpath(fname, root)
  fname = vim.fs.normalize(fname)
  root = strip_slash(vim.fs.normalize(root or vim.fn.getcwd()))
  if fname:sub(1, #root + 1) == root .. '/' then
    return fname:sub(#root + 2)
  end
  return fname
end

local function path_of(uri, client)
  return relpath(vim.uri_to_fname(uri), client and client.root_dir)
end

local function file_sym(uri, client)
  local path = path_of(uri, client)
  return { name = vim.fs.basename(path), kind = 1, path = path, line = 1 }
end

-- gopls names methods '(*Pod).portForwardIndicator' in documentSymbol but
-- 'portForwardIndicator' in call-hierarchy items. Keys are path:line:name, so
-- both routes must agree or a call-hierarchy child never matches its visit.
local function bare_name(name)
  return (name:gsub('^%b()%.', ''))
end

local function make_sym(name, kind, uri, range, sel, client)
  return {
    name = bare_name(name),
    kind = kind,
    path = path_of(uri, client),
    line = range.start.line + 1,
    col = (sel or range).start.character + 1,
  }
end

-- Exact-name lookup: bufnr() takes a pattern and can match another file.
local function loaded_buf(uri)
  local fname = vim.uri_to_fname(uri)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.api.nvim_buf_get_name(b) == fname then return b end
  end
end

local function stamp(uri)
  local b = loaded_buf(uri)
  if b then return 'tick:' .. vim.api.nvim_buf_get_changedtick(b) end
  local st = vim.uv.fs_stat(vim.uri_to_fname(uri))
  return st and ('mtime:' .. st.mtime.sec .. '.' .. st.mtime.nsec) or 'none'
end

local function fetch_symbols(client, uri, req_buf, cb)
  local s = stamp(uri)
  local hit = cache[uri]
  if hit and hit.stamp == s then return cb(hit.symbols) end
  local id = uri .. '\0' .. s
  if inflight[id] then return table.insert(inflight[id], cb) end
  inflight[id] = { cb }
  local function finish(symbols)
    local cbs = inflight[id]
    inflight[id] = nil
    cache[uri] = { stamp = s, symbols = symbols }
    for _, f in ipairs(cbs) do f(symbols) end
  end
  local ok = client:request('textDocument/documentSymbol', { textDocument = { uri = uri } },
    function(err, result) finish((not err and result) or {}) end,
    loaded_buf(uri) or req_buf)
  if not ok then finish({}) end
end

local function before_or_at(a, b)
  return a.line < b.line or (a.line == b.line and a.character <= b.character)
end

local function contains(range, pos)
  return before_or_at(range.start, pos) and before_or_at(pos, range['end'])
end

local function range_size(r)
  return (r['end'].line - r.start.line) * 1e6 + (r['end'].character - r.start.character)
end

local function innermost(symbols, uri, pos, client)
  if symbols[1] and symbols[1].location then
    -- Flat SymbolInformation[]: nesting is implied by range containment.
    local best
    for _, s in ipairs(symbols) do
      local loc = s.location
      if loc.uri == uri and contains(loc.range, pos)
        and (not best or range_size(loc.range) < range_size(best.location.range)) then
        best = s
      end
    end
    return best and make_sym(best.name, best.kind, uri, best.location.range, nil, client)
  end
  local found
  local level = symbols
  while level do
    local next_level
    for _, s in ipairs(level) do
      if s.range and contains(s.range, pos) then
        found, next_level = s, s.children
        break
      end
    end
    level = next_level
  end
  return found and make_sym(found.name, found.kind, uri, found.range, found.selectionRange, client)
end

-- uri + LSP position -> sym, via the client's documentSymbol for that uri.
local function resolve_uri(client, uri, pos, req_buf, cb)
  fetch_symbols(client, uri, req_buf, function(symbols)
    cb(innermost(symbols, uri, pos, client) or file_sym(uri, client))
  end)
end

local function symbol_client(bufnr)
  return vim.lsp.get_clients({ bufnr = bufnr, method = 'textDocument/documentSymbol' })[1]
end

local function lsp_position(bufnr, line, col, client)
  local text = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ''
  local enc = client and client.offset_encoding or 'utf-16'
  return { line = line - 1, character = vim.str_utfindex(text, enc, math.min(col, #text), false) }
end

-- line is 1-based, col 0-based bytes (the nvim_win_get_cursor convention).
-- Without a documentSymbol-capable client the answer is the file-level sym.
function M.resolve(bufnr, line, col, cb)
  bufnr = vim._resolve_bufnr(bufnr)
  local uri = vim.uri_from_bufnr(bufnr)
  local client = symbol_client(bufnr)
  if not client then return cb(file_sym(uri, nil)) end
  resolve_uri(client, uri, lsp_position(bufnr, line, col, client), bufnr, cb)
end

-- Location | Location[] | LocationLink[] -> { {uri, pos}, ... }. Copied out
-- of the result so nothing downstream can see (or touch) the caller's table.
local function locations(result)
  if type(result) ~= 'table' then return {} end
  if result.uri or result.targetUri then result = { result } end
  local out = {}
  for _, l in ipairs(result) do
    local uri = l.targetUri or l.uri
    local r = l.targetSelectionRange or l.targetRange or l.range
    if uri and r then
      table.insert(out, { uri = uri, pos = { line = r.start.line, character = r.start.character } })
    end
  end
  return out
end

local function hierarchy_syms(method, result, client)
  local out = {}
  for _, call in ipairs(type(result) == 'table' and result or {}) do
    local item = method == 'callHierarchy/incomingCalls' and call.from or call.to
    if item then
      local s = make_sym(item.name, item.kind, item.uri, item.range, item.selectionRange, client)
      s.count = math.max(#(call.fromRanges or {}), 1)
      table.insert(out, s)
    end
  end
  return out
end

-- Merge by key, first-seen order, summing counts.
local function dedupe(syms)
  local out, by = {}, {}
  for _, s in ipairs(syms) do
    local k = key(s)
    if by[k] then
      by[k].count = by[k].count + (s.count or 1)
    else
      local c = vim.deepcopy(s)
      c.count = s.count or 1
      by[k] = c
      table.insert(out, c)
    end
  end
  return out
end

local function resolve_all(client, locs, req_buf, cb)
  if #locs == 0 then return cb({}) end
  local syms, left = {}, #locs
  for i, l in ipairs(locs) do
    resolve_uri(client, l.uri, l.pos, req_buf, function(sym)
      syms[i] = sym
      left = left - 1
      if left == 0 then cb(syms) end
    end)
  end
end

-- Starts resolving `from` at request time (the cursor may move before the
-- response). Returns nil when the request is not the user's: its bufnr is not
-- the current buffer (diagnostics, background work).
local function begin(client, method, params, bufnr)
  local cur = vim.api.nvim_get_current_buf()
  if ((bufnr == nil or bufnr == 0) and cur or bufnr) ~= cur then return nil end
  local obs = { client = client, method = method, edge = EDGES[method], buf = cur }
  local uri, pos
  if type(params) == 'table' and params.position and params.textDocument then
    uri, pos = params.textDocument.uri, params.position
  else
    local c = vim.api.nvim_win_get_cursor(0)
    uri, pos = vim.uri_from_bufnr(cur), lsp_position(cur, c[1], c[2], client)
  end
  resolve_uri(client, uri, pos, cur, function(sym)
    obs.from = sym
    if obs.on_from then obs.on_from() end
  end)
  return obs
end

-- Read what the result says before the caller's handler runs; the handler
-- gets the result untouched and may do what it likes with it afterwards.
local function snapshot(obs, result)
  if obs.method:find('^callHierarchy/') then
    return { syms = hierarchy_syms(obs.method, result, obs.client) }
  end
  return { locs = locations(result) }
end

local function finish(obs, snap)
  local function emit_with(children)
    if #children == 0 then return end
    local function go()
      emit({ type = 'expand', from = obs.from, edge = obs.edge, children = dedupe(children) })
    end
    if obs.from then go() else obs.on_from = go end
  end
  if snap.syms then return emit_with(snap.syms) end
  resolve_all(obs.client, snap.locs, obs.buf, emit_with)
end

local function wrap(client)
  if wrapped[client] then return end
  wrapped[client] = true
  local orig = client.request
  client.request = function(self, method, params, handler, bufnr)
    if not EDGES[method] then return orig(self, method, params, handler, bufnr) end
    -- A nil handler means "use the configured default"; resolve it the same
    -- way Client:request does so the response can be observed on the way.
    local target = handler or self.handlers[method] or vim.lsp.handlers[method]
    local ok, obs = pcall(begin, self, method, params, bufnr)
    if not (ok and obs and target) then return orig(self, method, params, handler, bufnr) end
    return orig(self, method, params, function(err, result, ctx, config)
      local snap_ok, snap = false, nil
      if not err then snap_ok, snap = pcall(snapshot, obs, result) end
      local ret = target(err, result, ctx, config)
      if snap_ok then pcall(finish, obs, snap) end
      return ret
    end, bufnr)
  end
end

local function has_lsp(buf)
  return vim.bo[buf].buftype == '' and symbol_client(buf) ~= nil
end

-- A visit is a changed sym that got there by a jump: the buffer changed, or
-- the graph already knows the sym. Plain scrolling into an unknown sym in the
-- same buffer is not a visit (it would spray nodes); mark() covers that.
local function check(force)
  local buf = vim.api.nvim_get_current_buf()
  -- Without a client a jump can't be told from a not-yet-attached buffer;
  -- LspAttach re-checks. mark() still records the file-level sym.
  if not has_lsp(buf) and not (force and vim.bo[buf].buftype == '') then return end
  local c = vim.api.nvim_win_get_cursor(0)
  M.resolve(buf, c[1], c[2], function(sym)
    if vim.api.nvim_get_current_buf() ~= buf then return end
    local k = key(sym)
    if not force then
      if k == last.key then return end
      if buf == last.buf and not is_known(sym) then return end
    end
    last = { buf = buf, key = k }
    emit({ type = 'visit', sym = sym })
  end)
end

local function schedule_check()
  if not timer then timer = vim.uv.new_timer() end
  timer:stop()
  timer:start(M.DEBOUNCE_MS, 0, vim.schedule_wrap(function() check(false) end))
end

function M.on_event(cb)
  listener = cb
end

-- fn(sym) -> boolean: is this sym already a node or pending child?
function M.set_known(fn)
  is_known = fn or function() return false end
end

-- Force a visit of the cursor's sym, even if unknown or unchanged.
function M.mark()
  check(true)
end

function M.setup()
  local group = vim.api.nvim_create_augroup('mpataki.spelunk.lsp', { clear = true })
  vim.api.nvim_create_autocmd('LspAttach', {
    group = group,
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client then wrap(client) end
      -- A jump into a not-yet-attached file: BufEnter's check found no
      -- client, so re-check once one is there.
      if args.buf == vim.api.nvim_get_current_buf() then schedule_check() end
    end,
  })
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'BufEnter' }, {
    group = group,
    callback = schedule_check,
  })
  for _, client in ipairs(vim.lsp.get_clients()) do wrap(client) end
end

return M
