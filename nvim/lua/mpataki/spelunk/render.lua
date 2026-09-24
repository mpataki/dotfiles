-- Graph -> text. `tree` draws the dive as box-drawing lines for the split plus
-- an index (line -> sym) that <CR> resolves; `markdown` wraps the same tree with
-- a mermaid diagram and a notes list for the export file. Pure: reads the graph
-- through its public methods only, no buffers, no IO.
local graph = require('mpataki.spelunk.graph')

local M = {}

M.WIDTH = 40 -- default split width the current node's line is fitted into
M.LEFT_CAP = 28 -- left column (tree prefix + name) pads to at most this width
M.NOTE_CAP = 60

local HERE, GUTTER = '▶ ', '  ' -- 2-col gutter: marker on the current node only

local PLURAL = { caller = 'callers', callee = 'callees', def = 'definitions',
  impl = 'implementations', jump = 'jumps' }

local width = vim.fn.strdisplaywidth

local function arrow(edge)
  return edge == 'caller' and '←' or '→'
end

local function truncate(s, cap)
  if width(s) <= cap then return s end
  return vim.fn.strcharpart(s, 0, cap - 1) .. '…'
end

-- Longest common directory prefix (ending in '/') over every sym in the graph,
-- pending children included, so the column does not shift when you walk.
local function common_dir(g)
  local dir
  local function take(path)
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
  visit(g:root())
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

-- Rows are { left, path, sym, here }; the path column is placed once every row
-- is known. Note rows have no path and no sym.
local function rows(g)
  local out = {}
  local cur = graph.key(g:current())
  local drop = common_dir(g)
  local function short(sym)
    local p = sym.path
    if drop ~= '' and p:sub(1, #drop) == drop then p = p:sub(#drop + 1) end
    return p .. ':' .. sym.line
  end

  local function node(sym, prefix, head)
    local info = g:info(sym)
    out[#out + 1] = { left = head .. sym.name, path = short(sym), sym = sym, here = graph.key(sym) == cur }
    if info.note then out[#out + 1] = { left = prefix .. '· ' .. truncate(info.note, M.NOTE_CAP), path = '' } end
    local kids = {}
    if info.pruned and not in_subtree(g, sym, g:current()) then
      kids[1] = { text = '… (pruned)' }
    else
      local pending, order = {}, {}
      local here = graph.key(sym) == cur
      for _, c in ipairs(g:children(sym)) do
        if c.state == 'unexplored' then
          if here then
            kids[#kids + 1] = { pending = c }
          else
            if not pending[c.edge] then pending[c.edge] = 0; order[#order + 1] = c.edge end
            pending[c.edge] = pending[c.edge] + 1
          end
        else
          kids[#kids + 1] = { child = c }
        end
      end
      for _, edge in ipairs(order) do
        kids[#kids + 1] = { text = ('%d unexplored %s'):format(pending[edge], PLURAL[edge] or edge),
          glyph = '?' }
      end
    end
    for i, k in ipairs(kids) do
      local last = i == #kids
      local branch = prefix .. (last and '└─' or '├─')
      local cont = prefix .. (last and '    ' or '│   ')
      if k.child and k.child.tree then
        node(k.child.sym, cont, branch .. arrow(k.child.edge) .. ' ')
      elseif k.child then
        local s = k.child.sym
        out[#out + 1] = { left = branch .. '↩ ' .. s.name .. ' ' .. back_label(g, sym, k.child),
          path = short(s), sym = s }
      elseif k.pending then
        local s = k.pending.sym
        out[#out + 1] = { left = branch .. '?' .. arrow(k.pending.edge) .. ' ' .. s.name, path = short(s), sym = s }
      else
        out[#out + 1] = { left = branch .. (k.glyph and (k.glyph .. ' ') or '') .. k.text, path = '' }
      end
    end
  end

  node(g:root(), '', '')
  return out
end

local function pad(s, w)
  local sw = width(s)
  if sw >= w then return s .. '  ' end
  return s .. string.rep(' ', w - sw + 2)
end

-- Returns lines, index (line -> sym, nil holes) and the current node's line.
-- The path column sits where the current node's line still fits in
-- opts.width (default M.WIDTH); rows whose left side is wider overflow it.
function M.tree(g, opts)
  local limit = (opts and opts.width) or M.WIDTH
  local rs = rows(g)
  local lw, here = 0, nil
  for i, r in ipairs(rs) do
    if r.here then here = i end
    if r.path ~= '' then
      local w = width(r.left)
      if w <= M.LEFT_CAP and w > lw then lw = w end
    end
  end
  if here then
    lw = math.min(lw, limit - width(HERE) - 2 - width(rs[here].path))
  end
  local lines, index = {}, {}
  for i, r in ipairs(rs) do
    local line = r.path ~= '' and pad(r.left, lw) .. r.path or r.left
    lines[i] = ((r.here and HERE or GUTTER) .. line):gsub('%s+$', '')
    index[i] = r.sym
  end
  return lines, index, here
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
  node(g:root())
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
