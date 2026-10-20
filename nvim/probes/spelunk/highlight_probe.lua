-- Highlight spans: tier 2 on render.tree's 4th return (which text gets which
-- group), tier 3 on the live split (spans land as extmarks, groups resolve).
-- Hand-made syms, no LSP corpus.
local P = require('probe')
local graph = require('mpataki.spelunk.graph')
local render = require('mpataki.spelunk.render')
local HL = render.HL

local tag = tostring(math.random(1e6))
local function S(name, path, line)
  return { name = name .. tag, kind = 12, path = path, line = line }
end

local root = S('Root', 'internal/a/root.go', 10)
local kid = S('Kid', 'internal/a/kid.go', 20)
local impl = S('Impl', 'internal/b/impl.go', 30)
local g = graph.new(root)
g:expand(root, 'callee', { kid })
g:expand(root, 'impl', { impl })
g:expand(root, 'caller', { S('C1', 'internal/c/c.go', 1), S('C2', 'internal/c/c.go', 2) })
g:visit(kid)
g:note(kid, 'the note')
g:expand(kid, 'callee', { root, S('P1', 'internal/a/p.go', 5) })
g:expand(kid, 'caller', { S('P2', 'internal/a/q.go', 6) })

local lines, _, _, hls = render.tree(g)
P.ok(type(hls) == 'table' and #hls > 0, 'tree: 4th return is a non-empty span list')

-- Text under each span, grouped: what a reader sees in each colour.
local by = {}
local sane = true
for _, h in ipairs(hls) do
  local l = lines[h[1]]
  if not l or h[2] < 0 or h[3] > #l or h[2] >= h[3] then sane = false end
  local t = l and l:sub(h[2] + 1, h[3]) or ''
  by[h[4]] = by[h[4]] or {}
  by[h[4]][t] = true
end
P.ok(sane, 'spans: inside their line, non-empty, byte columns')

-- Byte columns survive multibyte gutter/connectors: a slice is valid UTF-8.
local utf8ok = true
for _, h in ipairs(hls) do
  if not pcall(vim.str_utf_pos, lines[h[1]]:sub(h[2] + 1, h[3])) or
    vim.fn.strchars(lines[h[1]]:sub(h[2] + 1, h[3])) == 0 then utf8ok = false end
end
P.ok(utf8ok, 'spans: never split a multibyte char')

local function has(group, text) return by[group] and by[group][text] end
P.ok(has(HL.here, '▶ ') and has(HL.here, kid.name), 'here: ▶ marker and current node name')
P.ok(has(HL.node, root.name), 'node: explored non-current name')
P.ok(has(HL.pending, 'P1' .. tag), 'pending: unexplored child name')
P.ok(has(HL.glyph, '? ') and has(HL.glyph, '↩ ') and has(HL.glyph, '· '), 'glyph: ? ↩ ·')
P.ok(has(HL.back, root.name), 'back: ↩ target name')
P.ok(has(HL.cycle, '(cycle)'), 'cycle: (cycle) label')
P.ok(has(HL.tag, '(caller)'), 'tag: pending (caller)')
P.ok(has(HL.note, 'the note'), 'note: note text')
P.ok(has(HL.summary, '2 unexplored callers'), 'summary: collapsed count')
P.ok(has(HL.path, 'a/kid.go:20'), 'path: path column, common internal/ dropped')
local connectors = true
for t in pairs(by[HL.tree] or {}) do
  if t:find('[^│├└─ ]') then connectors = false end
end
P.ok(by[HL.tree] and connectors, 'tree: connector spans hold only box-drawing and spaces')
local plainpad = true
for t in pairs(by[HL.path] or {}) do
  if t:find('^%s') then plainpad = false end
end
P.ok(plainpad, 'path: padding before the column is not highlighted')

-- Tier 3: the live split carries the spans as extmarks.
local spelunk = require('mpataki.spelunk')
spelunk.setup({ export_dir = vim.fn.tempname() .. '-spelunk' })
spelunk.start(root, 'hl')
spelunk.open()
local buf
for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  local b = vim.api.nvim_win_get_buf(w)
  if vim.bo[b].filetype == 'spelunk' then buf = b end
end
P.ok(buf ~= nil, 'split: open')
local ns = vim.api.nvim_get_namespaces().mpataki_spelunk
local function marks()
  return vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
end
local m = marks()
local groups = {}
for _, x in ipairs(m) do groups[x[4].hl_group] = true end
P.ok(#m > 0 and groups[HL.here] and groups[HL.path], 'split: extmarks with here + path groups')
for group in pairs(HL) do
  local name = HL[group]
  P.ok(next(vim.api.nvim_get_hl(0, { name = name, link = false })) ~= nil,
    'hl: ' .. name .. ' resolves to attributes')
end

-- Re-render replaces, not stacks.
local before = #marks()
spelunk.render()
spelunk.render()
P.eq(#marks(), before, 'split: re-render clears old extmarks')

-- Growing the graph re-highlights the new line.
spelunk.graph():visit(impl)
spelunk.render()
local found = false
for _, x in ipairs(marks()) do
  local l = vim.api.nvim_buf_get_lines(buf, x[2], x[2] + 1, false)[1]
  if x[4].hl_group == HL.here and l:sub(x[3] + 1, x[4].end_col) == impl.name then found = true end
end
P.ok(found, 'split: current node moves, its name gets SpelunkHere')

-- An override survives: default links never clobber a user's group.
vim.api.nvim_set_hl(0, 'SpelunkPath', { fg = '#123456' })
package.loaded['mpataki.spelunk'] = nil
require('mpataki.spelunk')
P.eq(vim.api.nvim_get_hl(0, { name = 'SpelunkPath' }).fg, 0x123456, 'hl: user override survives reload')

spelunk.stop()
P.done()
