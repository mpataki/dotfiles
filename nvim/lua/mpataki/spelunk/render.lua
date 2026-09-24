-- Graph -> text. `tree` draws the dive as box-drawing lines for the split plus
-- an index (line -> sym) that <CR> resolves; `markdown` wraps the same tree with
-- a mermaid diagram and a notes list for the export file. Pure: reads the graph
-- through its public methods only, no buffers, no IO.
local graph = require('mpataki.spelunk.graph')

local M = {}

M.LEFT_CAP = 28 -- left column (tree prefix + name) pads to at most this width
M.PATH_CAP = 32
M.NOTE_CAP = 60

local PLURAL = { caller = 'callers', callee = 'callees', def = 'definitions',
  impl = 'implementations', jump = 'jumps' }

local width = vim.fn.strdisplaywidth

local function glyph(c)
  if not c.tree then return '↩' end
  return c.edge == 'caller' and '←' or '→'
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

-- Rows are { left, path, tail, sym }; columns are padded once every row is known.
local function rows(g)
  local out = {}
  local cur = graph.key(g:current())
  local drop = common_dir(g)
  local function short(sym)
    local p = sym.path
    if drop ~= '' and p:sub(1, #drop) == drop then p = p:sub(#drop + 1) end
    return p .. ':' .. sym.line
  end
  local function node_tail(sym)
    local parts = {}
    if graph.key(sym) == cur then parts[#parts + 1] = '> YOU ARE HERE' end
    local info = g:info(sym)
    if info and info.note then parts[#parts + 1] = 'note: ' .. truncate(info.note, M.NOTE_CAP) end
    return table.concat(parts, '  ')
  end

  local function node(sym, prefix, head)
    out[#out + 1] = { left = head .. sym.name, path = short(sym), tail = node_tail(sym), sym = sym }
    local info = g:info(sym)
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
        node(k.child.sym, cont, branch .. glyph(k.child) .. ' ')
      elseif k.child then
        out[#out + 1] = { left = branch .. '↩ ' .. k.child.sym.name, path = '',
          tail = k.child.back and '(loop)' or '(jump)', sym = k.child.sym }
      elseif k.pending then
        local s = k.pending.sym
        out[#out + 1] = { left = branch .. '? ' .. s.name, path = short(s),
          tail = k.pending.edge, sym = s }
      else
        out[#out + 1] = { left = branch .. (k.glyph and (k.glyph .. ' ') or '') .. k.text,
          path = '', tail = '' }
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

function M.tree(g)
  local rs = rows(g)
  local lw, pw = 0, 0
  for _, r in ipairs(rs) do
    if r.path ~= '' or r.tail ~= '' then
      local w = width(r.left)
      if w <= M.LEFT_CAP and w > lw then lw = w end
      w = width(r.path)
      if w <= M.PATH_CAP and w > pw then pw = w end
    end
  end
  local lines, index = {}, {}
  for i, r in ipairs(rs) do
    local line = r.left
    if r.path ~= '' or r.tail ~= '' then
      line = pad(r.left, lw) .. (r.tail ~= '' and pad(r.path, pw) .. r.tail or r.path)
    end
    lines[i] = (line:gsub('%s+$', ''))
    index[i] = r.sym
  end
  return lines, index
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
