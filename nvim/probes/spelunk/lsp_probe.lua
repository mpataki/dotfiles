-- Tier 3: drives real vim.lsp.buf.* and telescope against gopls in ~/code/k9s
-- and asserts the events mpataki.spelunk.lsp emits. It cds into the k9s
-- checkout itself so gopls roots there whatever the caller's cwd.
local P = require('probe')
-- gopls must root in the corpus; run.sh starts from the dotfiles root.
local K9S = vim.fn.expand('~/code/k9s')
if vim.fn.isdirectory(K9S) == 0 then
  print('SKIP corpus missing: ' .. K9S)
  return P.done()
end
vim.cmd.cd(K9S)
-- Other lanes open the same k9s files concurrently. A swap-file ATTENTION
-- prompt reads stdin and hangs the probe forever when stdin is a terminal.
vim.o.swapfile = false
vim.opt.shortmess:append('A')
local lsp = require('mpataki.spelunk.lsp')
local Client = require('vim.lsp.client')

local POD = 'internal/view/pod.go'
local FWD = 'internal/watch/forwarders.go'
local SETTLE = lsp.DEBOUNCE_MS * 4 + 400

lsp.setup()
local events = {}
lsp.on_event(function(ev) table.insert(events, ev) end)

local function of(t)
  return vim.tbl_filter(function(e) return e.type == t end, events)
end
local function key(s)
  return s and (s.path .. ':' .. s.line .. ':' .. s.name) or 'nil'
end
local function child(ev, name)
  for _, c in ipairs(ev and ev.children or {}) do
    if c.name == name then return c end
  end
end

-- Run fn, wait for the first expand, then settle so a duplicate would show.
local function expand_after(fn)
  events = {}
  fn()
  P.wait(15000, function() return #of('expand') > 0 end)
  P.wait(SETTLE)
  return of('expand')
end

-- CursorMoved only fires from the main loop's normal-mode idle check, which
-- never runs while a -c luafile probe holds the loop in vim.wait. Fire the
-- event nvim would have fired; what is under test is the reaction to it.
local function move(line, col)
  vim.api.nvim_win_set_cursor(0, { line, col })
  vim.api.nvim_exec_autocmds('CursorMoved', { buffer = vim.api.nvim_get_current_buf() })
end

vim.cmd('edit ' .. POD)
local buf = vim.api.nvim_get_current_buf()
local c
P.wait(20000, function()
  c = vim.lsp.get_clients({ bufnr = buf, name = 'gopls' })[1]
  return c ~= nil
end)
if not P.ok(c ~= nil, 'gopls attached to pod.go') then return P.done() end

local uri = vim.uri_from_bufnr(buf)
local at66 = { textDocument = { uri = uri }, position = { line = 65, character = 17 } }
local ready = false
for _ = 1, 30 do
  local r = c:request_sync('textDocument/prepareCallHierarchy', at66, 5000, buf)
  if r and r.result and #r.result > 0 then ready = true break end
  P.wait(2000)
end
if not P.ok(ready, 'gopls workspace ready (prepareCallHierarchy non-empty)') then return P.done() end

-- resolve ----------------------------------------------------------------
local function resolve(b, line, col)
  local got
  lsp.resolve(b, line, col, function(s) got = s end)
  P.wait(5000, function() return got ~= nil end)
  return got
end

local s = resolve(buf, 66, 15)
P.eq(key(s), POD .. ':66:portForwardIndicator', 'resolve: method name is bare (receiver prefix dropped)')
P.eq(s and s.kind, 6, 'resolve: documentSymbol kind kept (Method)')
P.eq(s and s.col, 15, 'resolve: col is 1-based selectionRange start')
P.eq(key(resolve(buf, 61, 30)), POD .. ':50:NewPod', 'resolve: position inside NewPod body -> NewPod@50')
P.eq(key(resolve(buf, 45, 5)), POD .. ':45:Pod', 'resolve: struct line -> Pod')
P.eq(key(resolve(buf, 46, 2)), POD .. ':46:ResourceViewer', 'resolve: innermost descends into Pod\'s child field')
local f = resolve(buf, 1, 0)
P.eq(key(f), POD .. ':1:pod.go', 'resolve: no enclosing symbol -> file-level sym')
P.eq(f and f.kind, 1, 'resolve: file-level sym kind = File')

-- Cache: count documentSymbol requests with a probe-local spy on the client.
local ds = 0
local spied = c.request
c.request = function(self, method, ...)
  if method == 'textDocument/documentSymbol' then ds = ds + 1 end
  return spied(self, method, ...)
end
resolve(buf, 70, 2)
P.eq(ds, 0, 'resolve: cached per buffer + changedtick (no documentSymbol re-request)')
vim.api.nvim_buf_set_lines(buf, 0, 0, false, { '// spelunk probe' })
local after_edit = resolve(buf, 67, 15)
P.eq(ds, 1, 'resolve: changedtick bump re-requests documentSymbol')
P.eq(key(after_edit), POD .. ':67:portForwardIndicator', 'resolve: fresh symbols after the edit')
vim.api.nvim_buf_call(buf, function() vim.cmd('silent undo') end)
c.request = spied

-- expand: builtin vim.lsp.buf.* -------------------------------------------
local FROM = POD .. ':66:portForwardIndicator'
vim.api.nvim_win_set_cursor(0, { 66, 15 })

local ex = expand_after(function() vim.lsp.buf.definition() end)
P.eq(#ex, 1, 'definition: exactly one expand')
P.eq(key(ex[1] and ex[1].from), FROM, 'definition: from = portForwardIndicator')
P.eq(ex[1] and ex[1].edge, 'def', 'definition: edge def')
P.eq(ex[1] and #ex[1].children, 1, 'definition: one child')

vim.api.nvim_win_set_cursor(0, { 66, 15 })
ex = expand_after(function() vim.lsp.buf.references({ includeDeclaration = false }) end)
P.eq(#ex, 1, 'references: exactly one expand')
P.eq(key(ex[1] and ex[1].from), FROM, 'references: from = portForwardIndicator')
P.eq(ex[1] and ex[1].edge, 'caller', 'references: edge caller')
P.eq(ex[1] and #ex[1].children, 1, 'references: one child')
local np = child(ex[1], 'NewPod')
P.eq(key(np), POD .. ':50:NewPod', 'references: pod.go:61 collapses to enclosing NewPod@50')
P.eq(np and np.count, 1, 'references: NewPod count 1')
P.eq(#vim.fn.getqflist(), 1, 'references: builtin handler still filled quickfix')
vim.cmd('cclose')

vim.api.nvim_win_set_cursor(0, { 66, 15 })
ex = expand_after(function() vim.lsp.buf.incoming_calls() end)
P.eq(#ex, 1, 'incoming_calls: exactly one expand')
P.eq(key(ex[1] and ex[1].from), FROM, 'incoming_calls: from = portForwardIndicator')
P.eq(ex[1] and ex[1].edge, 'caller', 'incoming_calls: edge caller')
np = child(ex[1], 'NewPod')
P.eq(key(np), POD .. ':50:NewPod', 'incoming_calls: item maps to NewPod@50')
P.eq(np and np.kind, 12, 'incoming_calls: item kind kept')
P.eq(np and np.col, 6, 'incoming_calls: col from selectionRange')
P.eq(#vim.fn.getqflist(), 1, 'incoming_calls: nil handler resolved to the default (quickfix filled)')
vim.cmd('cclose')

vim.api.nvim_win_set_cursor(0, { 66, 15 })
ex = expand_after(function() vim.lsp.buf.outgoing_calls() end)
P.eq(#ex, 1, 'outgoing_calls: exactly one expand')
P.eq(key(ex[1] and ex[1].from), FROM, 'outgoing_calls: from = portForwardIndicator')
P.eq(ex[1] and ex[1].edge, 'callee', 'outgoing_calls: edge callee')
P.eq(ex[1] and #ex[1].children, 6, 'outgoing_calls: six callees')
P.eq(key(child(ex[1], 'IsPodForwarded')), FWD .. ':57:IsPodForwarded', 'outgoing_calls: IsPodForwarded@forwarders.go:57')
P.eq(child(ex[1], 'IsPodForwarded') and child(ex[1], 'IsPodForwarded').abs,
  vim.fs.normalize(vim.uv.fs_realpath(K9S) .. '/' .. FWD), 'outgoing_calls: child from another file carries its absolute path (abs)')
P.eq(child(ex[1], 'App') and child(ex[1], 'App').count, 2, 'outgoing_calls: App called twice -> count 2')
vim.cmd('cclose')

-- References inside one function collapse: `ff` is declared and used only in
-- portForwardIndicator. Driven through telescope (Mat's `gr`).
vim.api.nvim_win_set_cursor(0, { 67, 1 })
ex = expand_after(function() require('telescope.builtin').lsp_references() end)
P.eq(#ex, 1, 'telescope lsp_references: exactly one expand')
P.eq(ex[1] and ex[1].edge, 'caller', 'telescope lsp_references: edge caller')
P.eq(ex[1] and #ex[1].children, 1, 'telescope lsp_references: refs in one function -> one child')
P.eq(key(ex[1] and ex[1].children[1]), FROM, 'telescope lsp_references: child is the enclosing function')
P.eq(ex[1] and ex[1].children[1] and ex[1].children[1].count, 2, 'telescope lsp_references: count = locations collapsed')
local picker = P.picker()
if picker then require('telescope.actions').close(picker.prompt_bufnr) end
P.wait(200)
vim.cmd('stopinsert')
vim.api.nvim_set_current_buf(buf)

-- from = the asked-about symbol -------------------------------------------
-- Cursor on the call `ff.IsPodForwarded(...)` inside portForwardIndicator.
local CALL = { 76, 9 }
local FWD_FROM = FWD .. ':57:IsPodForwarded'
vim.api.nvim_win_set_cursor(0, CALL)
ex = expand_after(function() vim.lsp.buf.references() end)
P.eq(#ex, 1, 'references at a call site: exactly one expand')
P.eq(key(ex[1] and ex[1].from), FWD_FROM, 'references at a call site: from = definition IsPodForwarded, not the enclosing function')
P.eq(ex[1] and ex[1].edge, 'caller', 'references at a call site: edge caller')
local pfi = child(ex[1], 'portForwardIndicator')
P.eq(key(pfi), FROM, 'references at a call site: referrer portForwardIndicator is a child')
P.eq(pfi and pfi.count, 1, 'references at a call site: the call collapses into its function')
vim.cmd('cclose')
vim.api.nvim_set_current_buf(buf)

-- Whatever gopls prepares at the call site is the item; from must be it.
local prep = c:request_sync('textDocument/prepareCallHierarchy',
  { textDocument = { uri = uri }, position = { line = CALL[1] - 1, character = CALL[2] } }, 5000, buf)
local item = prep and prep.result and prep.result[1]
local item_key = item and (vim.uri_to_fname(item.uri):sub(#vim.fn.getcwd() + 2) .. ':' ..
  (item.range.start.line + 1) .. ':' .. item.name) or 'no item'
vim.api.nvim_win_set_cursor(0, CALL)
ex = expand_after(function() vim.lsp.buf.incoming_calls() end)
P.eq(#ex, 1, 'incoming_calls at a call site: exactly one expand')
P.eq(key(ex[1] and ex[1].from), item_key, 'incoming_calls at a call site: from = the prepared item')
P.eq(item_key, FWD_FROM, 'incoming_calls at a call site: gopls prepares the callee, not the enclosing function')
P.ok(child(ex[1], 'portForwardIndicator') ~= nil, 'incoming_calls at a call site: portForwardIndicator among the callers')
vim.cmd('cclose')
vim.api.nvim_set_current_buf(buf)

-- implementation on the embedded interface: hangs off the interface.
vim.api.nvim_win_set_cursor(0, { 46, 1 })
ex = expand_after(function() vim.lsp.buf.implementation() end)
P.eq(#ex, 1, 'implementation: exactly one expand')
P.eq(ex[1] and ex[1].from.name, 'ResourceViewer', 'implementation: from = the interface under the cursor')
P.eq(ex[1] and ex[1].from.path, 'internal/view/types.go', 'implementation: from resolved in the defining file')
P.eq(ex[1] and ex[1].edge, 'impl', 'implementation: edge impl')
P.ok(ex[1] and #ex[1].children > 1, 'implementation: implementers are children')
vim.cmd('cclose')
vim.api.nvim_set_current_buf(buf)

-- definition keeps the enclosing symbol even at a call site.
vim.api.nvim_win_set_cursor(0, CALL)
ex = expand_after(function() vim.lsp.buf.definition() end)
P.eq(key(ex[1] and ex[1].from), FROM, 'definition at a call site: from stays the enclosing function')
vim.cmd('edit ' .. POD)
vim.api.nvim_set_current_buf(buf)

-- pass-through ---------------------------------------------------------------
local refs = { textDocument = { uri = uri }, position = { line = 65, character = 17 },
  context = { includeDeclaration = true } }
local raw
Client.request(c, 'textDocument/references', refs, function(e, r) raw = { e, r } end, buf)
P.wait(5000, function() return raw ~= nil end)
local seen
events = {}
c:request('textDocument/references', refs, function(e, r, ctx) seen = { e, r, ctx } end, buf)
P.wait(5000, function() return seen ~= nil end)
P.ok(seen and seen[1] == nil and vim.deep_equal(seen[2], raw[2]), 'wrapper: caller handler gets the unwrapped result unchanged')
P.eq(seen and seen[3].method, 'textDocument/references', 'wrapper: handler ctx intact')

local hover
events = {}
c:request('textDocument/hover', at66, function(_, r) hover = r or false end, buf)
P.wait(5000, function() return hover ~= nil end)
P.wait(SETTLE)
P.ok(hover ~= nil and hover ~= false, 'wrapper: unobserved method (hover) passes through')
P.eq(#of('expand'), 0, 'wrapper: unobserved method emits nothing')

local fwd = vim.fn.bufadd(vim.fn.fnamemodify(FWD, ':p'))
vim.fn.bufload(fwd)
local bg
events = {}
c:request('textDocument/references', { textDocument = { uri = vim.uri_from_bufnr(fwd) },
  position = { line = 56, character = 22 }, context = { includeDeclaration = true } },
  function(_, r) bg = r or false end, fwd)
P.wait(5000, function() return bg ~= nil end)
P.wait(SETTLE)
P.ok(type(bg) == 'table' and #bg > 0, 'background: non-current-buffer request still answered')
P.eq(#of('expand'), 0, 'background: request for a non-current bufnr emits nothing')

local req_before = c.request
vim.api.nvim_exec_autocmds('LspAttach', { buffer = buf, data = { client_id = c.id } })
P.ok(c.request == req_before, 're-attach: client.request not re-wrapped')
vim.api.nvim_win_set_cursor(0, { 66, 15 })
ex = expand_after(function() vim.lsp.buf.definition() end)
P.eq(#ex, 1, 're-attach: definition still emits exactly one expand')

-- visit ------------------------------------------------------------------
-- A real cross-file `gd`: expand + a visit on the landed symbol.
vim.api.nvim_win_set_cursor(0, { 76, 9 })
events = {}
vim.lsp.buf.definition()
P.wait(15000, function() return #of('visit') > 0 and #of('expand') > 0 end)
P.wait(SETTLE)
ex = of('expand')
P.eq(#ex, 1, 'gd across files: one expand')
P.eq(key(ex[1] and ex[1].children[1]), FWD .. ':57:IsPodForwarded', 'gd across files: def child IsPodForwarded')
P.eq(#of('visit'), 1, 'gd across files: one visit')
P.eq(key(of('visit')[1] and of('visit')[1].sym), FWD .. ':57:IsPodForwarded', 'gd across files: visit lands on IsPodForwarded')

vim.cmd('edit ' .. POD)
P.wait(SETTLE)
events = {}
vim.cmd('edit ' .. FWD)
vim.api.nvim_win_set_cursor(0, { 70, 5 })
P.wait(10000, function() return #of('visit') > 0 end)
P.wait(SETTLE)
P.eq(#of('visit'), 1, 'jump to another file: exactly one visit')
P.eq(key(of('visit')[1] and of('visit')[1].sym), FWD .. ':69:IsContainerForwarded', 'jump to another file: visit carries the landed sym')

events = {}
move(82, 2)
P.wait(SETTLE)
P.eq(#of('visit'), 0, 'same buffer, unknown sym: no visit')

lsp.set_known(function(sym) return sym.name == 'Kill' end)
move(91, 2)
P.wait(SETTLE, function() return #of('visit') > 0 end)
P.wait(SETTLE)
P.eq(#of('visit'), 1, 'same buffer, known sym: one visit')
P.eq(key(of('visit')[1] and of('visit')[1].sym), FWD .. ':90:Kill', 'same buffer, known sym: visit is Kill')
lsp.set_known(nil)

events = {}
move(112, 2)
P.wait(SETTLE)
P.eq(#of('visit'), 0, 'mark: plain move into Dump emits nothing')
lsp.mark()
P.wait(5000, function() return #of('visit') > 0 end)
P.eq(#of('visit'), 1, 'mark: forces one visit')
P.eq(key(of('visit')[1] and of('visit')[1].sym), FWD .. ':111:Dump', 'mark: visit is Dump')

-- flat SymbolInformation: gopls returns hierarchical symbols, so an in-process
-- fake server answers documentSymbol with the flat shape.
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, 'p')
dir = vim.uv.fs_realpath(dir)
local fake_path = dir .. '/flat.fake'
local lines = {}
for i = 1, 14 do lines[i] = 'line ' .. i end
vim.fn.writefile(lines, fake_path)
vim.cmd('edit ' .. vim.fn.fnameescape(fake_path))
local fbuf = vim.api.nvim_get_current_buf()
local furi = vim.uri_from_bufnr(fbuf)
local function rng(a, b) return { start = { line = a, character = 0 }, ['end'] = { line = b, character = 0 } } end
local flat = {
  { name = 'Outer', kind = 5, location = { uri = furi, range = rng(0, 10) } },
  { name = 'inner', kind = 6, containerName = 'Outer', location = { uri = furi, range = rng(2, 5) } },
}
local def_mode = 'empty'
local refs_mode = 'good'
local function fake_answer(method)
  if method == 'initialize' then
    return nil, { capabilities = { documentSymbolProvider = true, definitionProvider = true, referencesProvider = true } }
  elseif method == 'textDocument/documentSymbol' then
    return nil, flat
  elseif method == 'textDocument/definition' then
    if def_mode == 'error' then return { code = -32603, message = 'probe: definition fails' }, nil end
    return nil, {}
  elseif method == 'textDocument/references' then
    -- 'bad': a range with no start, so reading the result fails.
    if refs_mode == 'bad' then return nil, { { uri = furi, range = {} } } end
    return nil, { { uri = furi, range = rng(8, 8) }, { uri = furi, range = rng(9, 9) } }
  end
end
local id = 0
vim.lsp.start({
  name = 'spelunk-fake',
  root_dir = dir,
  cmd = function()
    return {
      request = function(method, _, cb)
        id = id + 1
        local err, res = fake_answer(method)
        vim.schedule(function() cb(err, res) end)
        return true, id
      end,
      notify = function() return true end,
      is_closing = function() return false end,
      terminate = function() end,
    }
  end,
}, { bufnr = fbuf })
P.wait(5000, function() return #vim.lsp.get_clients({ bufnr = fbuf, name = 'spelunk-fake' }) > 0 end)
P.eq(key(resolve(fbuf, 4, 0)), 'flat.fake:3:inner', 'flat SymbolInformation: innermost by range')
P.eq(key(resolve(fbuf, 9, 0)), 'flat.fake:1:Outer', 'flat SymbolInformation: outer when only it contains')
P.eq(key(resolve(fbuf, 13, 0)), 'flat.fake:1:flat.fake', 'flat SymbolInformation: outside all -> file-level sym')


-- references fallback: the definition lookup yields nothing, or errors.
for _, mode in ipairs({ 'empty', 'error' }) do
  def_mode = mode
  vim.api.nvim_set_current_buf(fbuf)
  vim.api.nvim_win_set_cursor(0, { 4, 0 })
  ex = expand_after(function() vim.lsp.buf.references() end)
  P.eq(#ex, 1, 'references fallback (' .. mode .. ' definition): one expand')
  P.eq(key(ex[1] and ex[1].from), 'flat.fake:3:inner', 'references fallback (' .. mode .. ' definition): from = enclosing symbol')
  P.eq(key(ex[1] and ex[1].children[1]), 'flat.fake:1:Outer', 'references fallback (' .. mode .. ' definition): children still resolved')
  vim.cmd('cclose')
end

-- capture failure: surfaces once per method, the caller's handler still runs.
refs_mode = 'bad'
local warns, handled, notify = {}, 0, vim.notify
vim.notify = function(msg, ...) warns[#warns + 1] = msg; return notify(msg, ...) end
local fclient = vim.lsp.get_clients({ bufnr = fbuf, name = 'spelunk-fake' })[1]
local rparams = { textDocument = { uri = furi }, position = { line = 3, character = 0 },
  context = { includeDeclaration = true } }
for _ = 1, 2 do
  fclient:request('textDocument/references', rparams, function() handled = handled + 1 end, fbuf)
end
P.wait(5000, function() return handled == 2 end)
P.wait(SETTLE)
vim.notify = notify
refs_mode = 'good'
local capture = vim.tbl_filter(function(m) return m:find('capture failed (textDocument/references)', 1, true) end, warns)
P.eq(handled, 2, 'capture failure: the caller\'s handler still runs')
P.eq(#capture, 1, 'capture failure: notifies once per method')

P.eq(package.loaded['mpataki.spelunk.graph'], nil, 'module stays graph-free (graph never loaded)')
P.done()
