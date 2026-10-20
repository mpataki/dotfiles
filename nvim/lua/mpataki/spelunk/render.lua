-- Graph -> text. `tree` draws the dive as box-drawing lines for the split plus
-- an index (line -> sym) that <CR> resolves and highlight spans for the split; `markdown` wraps the same tree with
-- a mermaid diagram and a notes list for the export file. Pure: reads the graph
-- through its public methods only, no buffers, no IO.
local graph = require('mpataki.spelunk.graph')

local M = {}

M.WIDTH = 40 -- default split width the current node's line is fitted into
M.LEFT_CAP = 28 -- left column (tree prefix + name) pads to at most this width
M.NOTE_CAP = 60
M.FRONTIER_CAP = 12 -- pending lines listed under the current node before '… N more'

local HERE, GUTTER = '▶ ', '  ' -- 2-col gutter: marker on the current node only

local PLURAL = { caller = 'callers', callee = 'callees', def = 'definitions',
  impl = 'implementations', jump = 'jumps' }

local width = vim.fn.strdisplaywidth

-- Highlight group per segment kind. init.lua declares them as default links,
-- so a theme or override can restyle any one of them.
local HL = {
  here = 'SpelunkHere', -- ▶ and the current node's name
  node = 'SpelunkNode', -- an explored node's name
  tree = 'SpelunkTree', -- box-drawing connectors
  glyph = 'SpelunkGlyph', -- ? ↩ … markers
  pending = 'SpelunkPending', -- an unexplored child's name
  back = 'SpelunkBack', -- a ↩ target's name
  tag = 'SpelunkTag', -- (impl) (jump) (caller) (seen)
  cycle = 'SpelunkCycle', -- (cycle)
  note = 'SpelunkNote',
  summary = 'SpelunkSummary', -- counts, (pruned)
  path = 'SpelunkPath',
}
M.HL = HL

-- A row's left side is a list of { text, hl } segments; hl nil draws plain.
local function flat(segs)
  local t = {}
  for i, sg in ipairs(segs) do t[i] = sg[1] end
  return table.concat(t)
end

-- Nesting reads "parent calls child", so plain calls and defs carry no glyph;
-- the edges that mean something else say so. Pending callers sit under the
-- node they call until walked, when they move above it.
local TREE_TAG = { impl = '(impl)', jump = '(jump)' }
local PENDING_TAG = { caller = '(caller)', impl = '(impl)' }

local function truncate(s, cap)
  if width(s) <= cap then return s end
  return vim.fn.strcharpart(s, 0, cap - 1) .. '…'
end

-- Sym paths are relative to the LSP client root; an absolute one is outside
-- it (the module cache, GOROOT).
local function external(sym)
  return sym.path:sub(1, 1) == '/'
end

-- Longest common directory prefix (ending in '/') over every in-root sym in
-- the graph, pending children included, so the column does not shift when you
-- walk. External paths would collapse it to '/'.
local function common_dir(g)
  local dir
  local function take(path)
    if path:sub(1, 1) == '/' then return end
    local d = path:match('^(.*/)') or ''
    if dir == nil then dir = d; return end
    local i = 0
    while i < #dir and i < #d and dir:byte(i + 1) == d:byte(i + 1) do i = i + 1 end
    dir = dir:sub(1, i):match('^(.*/)') or ''
  end
  local function visit(sym)
    take(sym.path)
    for _, c in ipairs(g:children(sym)) do
      if c.tree then visit(c.sym) else take(c.sym.path) end
    end
  end
  for _, r in ipairs(g:roots()) do visit(r) end
  return dir or ''
end

local function in_subtree(g, top, sym)
  local tk = graph.key(top)
  local s = sym
  while s do
    if graph.key(s) == tk then return true end
    local info = g:info(s)
    s = info and info.parent
  end
  return false
end

-- A ↩ line under `at`: a cycle when the target is on the way up from `at`,
-- a jump when you navigated there, else two paths meeting.
local function back_label(g, at, c)
  if in_subtree(g, c.sym, at) then return '(cycle)' end
  return c.edge == 'jump' and '(jump)' or '(seen)'
end

-- Rows are { left = segments, path, sym, here }; the path column is placed once
-- every row is known. Note rows have no path and no sym.
local function rows(g)
  local out = {}
  local cur = graph.key(g:current())
  local drop = common_dir(g)
  local function short(sym)
    local p = sym.path
    if external(sym) then return (p:match('([^/]+/[^/]+)$') or p) .. ':' .. sym.line end
    if drop ~= '' and p:sub(1, #drop) == drop then p = p:sub(#drop + 1) end
    return p .. ':' .. sym.line
  end

  local function node(sym, prefix, head, tag)
    local info = g:info(sym)
    local here = graph.key(sym) == cur
    local left = { { head, HL.tree }, { sym.name, here and HL.here or HL.node } }
    if tag then vim.list_extend(left, { { ' ' }, { tag, HL.tag } }) end
    out[#out + 1] = { left = left, path = short(sym), sym = sym, here = here }
    if info.note then
      out[#out + 1] = { left = { { prefix, HL.tree }, { '· ', HL.glyph },
        { truncate(info.note, M.NOTE_CAP), HL.note } }, path = '' }
    end
    local kids = {}
    if info.pruned and not in_subtree(g, sym, g:current()) then
      kids[1] = { text = '(pruned)', glyph = '…' }
    else
      -- Pending children, one per sym (a sym pending under two edges is one
      -- choice): first-listed position, latest entry's edge (the one a visit
      -- walks). Externals only ever count.
      -- Back-edges fold by target too: two facts reaching the same known node
      -- from here are one thing to read ("this leads back to X").
      local pend, at, ext, n_ext, seen_back = {}, {}, {}, 0, {}
      for _, c in ipairs(g:children(sym)) do
        local k = graph.key(c.sym)
        if c.state ~= 'unexplored' then
          if c.tree or not seen_back[k] then kids[#kids + 1] = { child = c } end
          if not c.tree then seen_back[k] = true end
        elseif external(c.sym) then
          if not ext[k] then ext[k], n_ext = true, n_ext + 1 end
        elseif at[k] then
          pend[at[k]] = c
        else
          pend[#pend + 1] = c
          at[k] = #pend
        end
      end
      if graph.key(sym) == cur then
        for i = 1, math.min(#pend, M.FRONTIER_CAP) do kids[#kids + 1] = { pending = pend[i] } end
        if #pend > M.FRONTIER_CAP then
          kids[#kids + 1] = { text = ('%d more'):format(#pend - M.FRONTIER_CAP), glyph = '…' }
        end
      else
        local count, order = {}, {}
        for _, c in ipairs(pend) do
          if not count[c.edge] then count[c.edge] = 0; order[#order + 1] = c.edge end
          count[c.edge] = count[c.edge] + 1
        end
        for _, edge in ipairs(order) do
          kids[#kids + 1] = { text = ('%d unexplored %s'):format(count[edge], PLURAL[edge] or edge),
            glyph = '?' }
        end
      end
      if n_ext > 0 then kids[#kids + 1] = { text = n_ext .. ' external', glyph = '?' } end
    end
    for i, k in ipairs(kids) do
      local last = i == #kids
      local branch = prefix .. (last and '└─' or '├─')
      -- 3 wide: a child's connector sits under its parent's first letter.
      local cont = prefix .. (last and '   ' or '│  ')
      if k.child and k.child.tree then
        node(k.child.sym, cont, branch .. ' ', TREE_TAG[k.child.edge])
      elseif k.child then
        local s = k.child.sym
        local lbl = back_label(g, sym, k.child)
        out[#out + 1] = { left = { { branch, HL.tree }, { '↩ ', HL.glyph }, { s.name, HL.back }, { ' ' },
          { lbl, lbl == '(cycle)' and HL.cycle or HL.tag } }, path = short(s), sym = s }
      elseif k.pending then
        local s = k.pending.sym
        local left = { { branch, HL.tree }, { '? ', HL.glyph }, { s.name, HL.pending } }
        local ptag = PENDING_TAG[k.pending.edge]
        if ptag then vim.list_extend(left, { { ' ' }, { ptag, HL.tag } }) end
        out[#out + 1] = { left = left, path = short(s), sym = s }
      else
        local left = { { branch, HL.tree } }
        if k.glyph then left[#left + 1] = { k.glyph .. ' ', HL.glyph } end
        left[#left + 1] = { k.text, HL.summary }
        out[#out + 1] = { left = left, path = '' }
      end
    end
  end

  for _, r in ipairs(g:roots()) do node(r, '', '') end
  return out
end

local function pad(s, w)
  local sw = width(s)
  if sw >= w then return s .. '  ' end
  return s .. string.rep(' ', w - sw + 2)
end

-- Returns lines, index (line -> sym, nil holes), the current node's line and
-- highlight spans: { line, col, end_col, group }, 1-based line, 0-based
-- end-exclusive byte columns (extmark-ready). The path column sits where the
-- current node's line still fits in opts.width (default M.WIDTH); rows whose
-- left side is wider overflow it.
function M.tree(g, opts)
  local limit = (opts and opts.width) or M.WIDTH
  local rs = rows(g)
  local lw, here = 0, nil
  for i, r in ipairs(rs) do
    r.text = flat(r.left)
    if r.here then here = i end
    if r.path ~= '' then
      local w = width(r.text)
      if w <= M.LEFT_CAP and w > lw then lw = w end
    end
  end
  if here then
    lw = math.min(lw, limit - width(HERE) - 2 - width(rs[here].path))
  end
  local lines, index, hls = {}, {}, {}
  for i, r in ipairs(rs) do
    local segs = { { r.here and HERE or GUTTER, r.here and HL.here or nil } }
    vim.list_extend(segs, r.left)
    if r.path ~= '' then
      segs[#segs + 1] = { pad(r.text, lw):sub(#r.text + 1) }
      segs[#segs + 1] = { r.path, HL.path }
    end
    local line = flat(segs):gsub('%s+$', '')
    local col = 0
    for _, sg in ipairs(segs) do
      local e = math.min(col + #sg[1], #line)
      if sg[2] and e > col then hls[#hls + 1] = { i, col, e, sg[2] } end
      col = col + #sg[1]
    end
    lines[i] = line
    index[i] = r.sym
  end
  return lines, index, here, hls
end

local function mid(key)
  return 'n' .. vim.fn.sha256(key):sub(1, 10)
end

local function label(s)
  return '"' .. s:gsub('"', '#quot;') .. '"'
end

-- Mermaid mirrors the tree's visibility: explored nodes only (the frontier lives
-- in the tree block), nothing below a pruned node. Edges are emitted after every
-- visible node is known, so a back-edge into a pruned subtree is dropped instead
-- of conjuring a bare, unlabeled node.
local function mermaid(g)
  local out = { '```mermaid', 'graph TD' }
  local visible, order, notes = {}, {}, {}
  local cur = g:current()
  local function node(sym)
    local k = graph.key(sym)
    visible[k] = true
    order[#order + 1] = sym
    out[#out + 1] = '  ' .. mid(k) .. '[' .. label(sym.name) .. ']'
    local info = g:info(sym)
    if info.note then notes[#notes + 1] = { sym = sym, note = info.note } end
    if info.pruned and not in_subtree(g, sym, cur) then return end
    for _, c in ipairs(g:children(sym)) do
      if c.tree then node(c.sym) end
    end
  end
  for _, r in ipairs(g:roots()) do node(r) end
  for _, sym in ipairs(order) do
    local from = graph.key(sym)
    local info = g:info(sym)
    if not (info.pruned and not in_subtree(g, sym, cur)) then
      for _, c in ipairs(g:children(sym)) do
        local to = graph.key(c.sym)
        if c.state == 'explored' and visible[to] then
          out[#out + 1] = ('  %s %s|%s| %s'):format(mid(from), c.back and '-.->' or '-->',
            c.edge, mid(to))
        end
      end
    end
  end
  out[#out + 1] = '  style ' .. mid(graph.key(cur)) .. ' stroke:#f38ba8,stroke-width:3px'
  out[#out + 1] = '```'
  return out, notes
end

function M.markdown(g, name)
  local out = { '# spelunk: ' .. name, '' }
  local diagram, notes = mermaid(g)
  vim.list_extend(out, diagram)
  out[#out + 1] = ''
  out[#out + 1] = '```text'
  vim.list_extend(out, (M.tree(g)))
  out[#out + 1] = '```'
  out[#out + 1] = ''
  out[#out + 1] = '## Notes'
  out[#out + 1] = ''
  if #notes == 0 then out[#out + 1] = '_(none)_' end
  for _, n in ipairs(notes) do
    out[#out + 1] = ('- **%s** %s:%d — %s'):format(n.sym.name, n.sym.path, n.sym.line, n.note)
  end
  return table.concat(out, '\n') .. '\n'
end

return M
