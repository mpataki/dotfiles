local P = require('probe')
local graph = require('mpataki.spelunk.graph')
local render = require('mpataki.spelunk.render')

local tag = tostring(math.random(1e6))
local function S(name, path, line)
  return { name = name .. tag, kind = 12, path = path, line = line }
end
local function find(lines, pat)
  for i, l in ipairs(lines) do
    if l:find(pat, 1, true) then return i, l end
  end
end

local root = S('NewPod', 'internal/view/pod.go', 50)
local pfi = S('portForwardIndicator', 'internal/view/pod.go', 66)
local rows = S('RowsRange', 'internal/model1/table_data.go', 98)
local fwd = S('IsPodForwarded', 'internal/watch/forwarders.go', 57)

local g = graph.new(root)
g:expand(root, 'callee', { pfi })
g:expand(root, 'caller', { S('C1', 'internal/a/c.go', 1), S('C2', 'internal/a/d.go', 2) })
g:visit(pfi)
g:expand(pfi, 'callee', { rows, fwd, S('X1', 'internal/x/x.go', 1), S('X2', 'internal/x/x.go', 9),
  S('X3', 'internal/x/y.go', 1), S('X4', 'internal/x/z.go', 1) })
-- Walk fwd before rows: the tree must follow visit order, not expand order.
g:visit(fwd)
g:note(fwd, 'the real check')
g:expand(fwd, 'caller', { root })
g:visit(pfi)
g:visit(rows)

local lines, index = render.tree(g)
-- index has nil holes, so # is meaningless on it; check every slot instead.
local parallel = table.maxn(index) <= #lines
for i = 1, #lines do
  if index[i] ~= nil and type(index[i].name) ~= 'string' then parallel = false end
end
P.ok(parallel, 'index parallel to lines (sym or nil per line)')

-- DFS first-visit order
local ir, lr = find(lines, rows.name)
local iff, lf = find(lines, fwd.name)
P.ok(iff and ir and iff < ir, 'tree: DFS in first-visit order (fwd walked before rows)')
P.eq(lines[1]:match('^  (%S+)'), root.name, 'tree: root on line 1, no connector (after the gutter)')

-- glyphs
P.ok(lf:find('├─→ ' .. fwd.name, 1, true) ~= nil, 'tree: → glyph for callee')
local il, ll = find(lines, '↩ ' .. root.name)
P.ok(ll and ll:find('↩ ' .. root.name .. ' (cycle)', 1, true) ~= nil,
  'decision 4: ↩ onto an ancestor is labelled (cycle)')
P.ok(ll and ll:find('view/pod.go:50', 1, true) ~= nil, 'decision 4: ↩ line carries the target path')
P.ok(il and il == iff + 2, 'tree: back-edge drawn under the node it came from (decision 2: after its note line)')
P.eq(index[il] and graph.key(index[il]), graph.key(root), 'index: back-edge line maps to target sym')
local ic, lc = find(lines, '2 unexplored callers')
P.ok(lc and lc:find('└─? ', 1, true) ~= nil, 'tree: ? glyph + count for collapsed frontier')
P.eq(index[ic], nil, 'index: count line is nil')
P.ok(lr:find('^▶ ') ~= nil, 'decision 1: ▶ in the gutter on the current node')
local marked, gutters = 0, true
for _, l in ipairs(lines) do
  if l:find('^▶ ') then marked = marked + 1 elseif not l:find('^  ') then gutters = false end
end
P.ok(marked == 1 and gutters, 'decision 1: every line starts with a 2-col gutter, ▶ on one line only')
P.ok(not table.concat(lines, '\n'):find('YOU ARE HERE', 1, true), 'decision 1: no > YOU ARE HERE suffix')
local _, x1 = find(lines, 'X1' .. tag)
P.eq(x1, nil, 'tree: sibling frontier of pfi not individually listed when rows is current')

-- current's own frontier expands to individual children
g:expand(rows, 'callee', { S('R1', 'internal/q/r.go', 4), S('R2', 'internal/q/r.go', 8) })
lines, index = render.tree(g)
local i1, l1 = find(lines, '?→ R1' .. tag)
P.ok(l1 ~= nil and find(lines, '2 unexplored callees') == nil,
  'tree: frontier under current expands to individual unexplored children')
P.eq(index[i1] and graph.key(index[i1]), graph.key(S('R1', 'internal/q/r.go', 4)),
  'index: expanded frontier line maps to its sym')
P.ok(find(lines, '4 unexplored callees') ~= nil, 'tree: non-current frontier collapsed to a count')

-- note on its own line, path prefix dropped
local ni, nl = find(lines, fwd.name)
P.ok(nl:find('watch/forwarders.go:57$') ~= nil, 'decision 2: nothing past the path column on a node line')
P.eq(lines[ni + 1], '  │   │   · the real check', 'decision 2: note on its own line, indented past the connector')
P.eq(index[ni + 1], nil, 'decision 2: note line index is nil')
P.ok(nl:find('internal/', 1, true) == nil and lines[1]:find('view/pod.go:50', 1, true) ~= nil,
  'tree: common path prefix dropped')
local gi = graph.new(S('A', 'lib/a.go', 1))
gi:visit(S('B', 'cmd/b.go', 1))
P.ok(render.tree(gi)[1]:find('lib/a.go:1', 1, true) ~= nil, 'tree: no common prefix keeps full paths')

-- index maps node lines to syms
local ip = find(lines, pfi.name)
P.eq(graph.key(index[ip]), graph.key(pfi), 'index: node line maps to its sym')
P.eq(graph.key(index[1]), graph.key(root), 'index: root line maps to root')

-- pruned subtree is one line
g:visit(root)
g:prune(pfi)
lines, index = render.tree(g)
local pl = find(lines, '… (pruned)')
P.ok(pl ~= nil and find(lines, rows.name) == nil and find(lines, fwd.name) == nil,
  'tree: pruned subtree renders as one … (pruned) line')
P.eq(pl and index[pl], nil, 'index: pruned line is nil')
P.eq(graph.key(index[pl - 1]), graph.key(pfi), 'tree: pruned node itself still listed')
g:prune(pfi, false)

-- round-trip renders identical lines
local want = render.tree(g)
local back = graph.deserialize(vim.json.decode(vim.json.encode(g:serialize())))
P.eq(table.concat(render.tree(back), '\n'), table.concat(want, '\n'),
  'round-trip: deserialize(serialize(g)) renders identical lines')
P.eq(render.markdown(back, 's'), render.markdown(g, 's'), 'round-trip: identical markdown')

-- markdown
g:visit(pfi)
g:note(pfi, 'hub')
local md = render.markdown(g, 'dive-1')
P.ok(md:find('^# spelunk: dive%-1\n') ~= nil, 'markdown: # spelunk: <session> header')
P.ok(md:find('```mermaid\ngraph TD\n', 1, true) ~= nil, 'markdown: mermaid graph TD block')
local fid, rid = md:match('\n  (n%x+) %-%.%->|caller| (n%x+)\n')
P.ok(fid ~= nil and fid ~= rid, 'markdown: back-edge dashed with edge-kind label')
P.ok(md:find('%-%->|callee|') ~= nil, 'markdown: tree edge solid with edge-kind label')
local cid = md:match('\n  (n%x+)%["' .. pfi.name .. '"%]')
P.ok(cid ~= nil, 'markdown: node id safe (n + hex), label = name')
P.ok(md:find('\n  style ' .. cid .. ' ', 1, true) ~= nil, 'markdown: current node styled')
P.ok(md:find('```text\n' .. table.concat(render.tree(g), '\n') .. '\n```', 1, true) ~= nil,
  'markdown: tree in a fenced block')
P.ok(md:find('\n## Notes\n', 1, true) ~= nil, 'markdown: ## Notes section')
P.ok(md:find('\n- **' .. fwd.name .. '** internal/watch/forwarders.go:57 — the real check\n', 1, true) ~= nil,
  'markdown: note as - **name** path:line — note')
P.ok(md:find('\n- **' .. pfi.name .. '** internal/view/pod.go:66 — hub\n', 1, true) ~= nil,
  'markdown: every noted node listed')

local q = graph.new({ name = 'Pod."x" [y]', kind = 6, path = 'a.go', line = 1 })
local qmd = render.markdown(q, 'q')
P.ok(qmd:find('["Pod.#quot;x#quot; [y]"]', 1, true) ~= nil, 'markdown: quotes in label escaped')
P.ok(qmd:find('_(none)_', 1, true) ~= nil, 'markdown: empty notes placeholder')

-- decision 4: two paths meeting is (seen), not a cycle
local ra, rb, rc = S('RA', 'lib/a.go', 1), S('RB', 'lib/b.go', 1), S('RC', 'lib/c.go', 1)
local gc = graph.new(ra)
gc:expand(ra, 'callee', { rb, rc })
gc:visit(rb)
gc:expand(rb, 'callee', { S('RD', 'lib/d.go', 1) })
gc:visit(S('RD', 'lib/d.go', 1))
gc:visit(ra)
gc:visit(rc)
gc:expand(rc, 'caller', { S('RD', 'lib/d.go', 1) })
local _, seen = find(render.tree(gc), '↩ RD' .. tag)
P.ok(seen and seen:find('(seen)', 1, true) and seen:find('d.go:1', 1, true),
  'decision 4: ↩ onto a node elsewhere is labelled (seen), with its path')

-- decision 1: the path column moves left so the current node's line fits,
-- even when deeper rows would pad it past the split width
local top = S('Top', 'v/app.go', 10)
local deep = graph.new(top)
local at, lvl1 = top, nil
for d = 1, 4 do
  local n = S('Nested' .. d, 'm/lvl.go', 100 + d)
  deep:expand(at, 'callee', { n })
  deep:visit(n)
  lvl1 = lvl1 or n
  at = n
end
deep:visit(lvl1)
local dl, _, dh = render.tree(deep)
P.ok(dh and dl[dh]:find('^▶ ') and vim.fn.strdisplaywidth(dl[dh]) <= render.WIDTH,
  'decision 1: current node line <= ' .. render.WIDTH .. ' cells — ' .. tostring(dh and dl[dh]))
deep:visit(top)
dl, _, dh = render.tree(deep)
P.ok(dh == 1 and vim.fn.strdisplaywidth(dl[1]) <= render.WIDTH,
  'decision 1: tree returns the current line, fitted — ' .. dl[1])

-- decision 5: externals collapse
local zl = '/Users/x/go/pkg/mod/github.com/rs/zerolog@v1.32.0/event.go'
local er = '/opt/homebrew/Cellar/go/1.26.7/libexec/src/errors/errors.go'
local eroot = S('run', 'internal/view/command.go', 141)
local ge = graph.new(eroot)
ge:expand(eroot, 'callee', { S('exec', 'internal/view/command.go', 298), S('Msg', zl, 106),
  S('Msgf', zl, 120), S('New', er, 64), S('inject', 'internal/view/app.go', 700) })
ge:expand(eroot, 'caller', { S('Msg', zl, 106) })
local el, ei = render.tree(ge)
local xi, xl = find(el, '? 3 external')
P.ok(xl and xl:find('└─%? 3 external$') and ei[xi] == nil,
  'decision 5: pending externals are one "? N external" line (unique syms, index nil)')
P.ok(not find(el, 'Msg' .. tag) and not find(el, 'New' .. tag), 'decision 5: externals never listed individually')
P.eq(#ge:frontier(), 5, 'decision 5: externals stay in frontier()')
P.ok(find(el, 'command.go:298') and not find(el, 'internal/', 1), 'decision 5: externals excluded from the common prefix')
ge:visit(S('Msg', zl, 106))
el = render.tree(ge)
P.ok(find(el, 'zerolog@v1.32.0/event.go:106') and not find(el, '/Users/x'),
  'decision 5: explored external node shows its last two path segments')
ge:visit(eroot)
el = render.tree(ge)
P.ok(find(el, '? 2 external'), 'decision 5: explored external leaves the count')

-- decision 8: the expanded frontier under current is capped
local croot = S('hub', 'lib/hub.go', 1)
local gcap = graph.new(croot)
local many = {}
for n = 1, 15 do many[n] = S('p' .. n, 'lib/p.go', n) end
gcap:expand(croot, 'callee', many)
gcap:expand(croot, 'caller', { many[1], many[2] })
local cl, ci = render.tree(gcap)
local listed = #vim.tbl_filter(function(l) return l:find('?←', 1, true) or l:find('?→', 1, true) end, cl)
local mi, ml = find(cl, '… 3 more')
P.ok(listed == render.FRONTIER_CAP and ml and ci[mi] == nil,
  'decision 8: 12 pending lines under current, then one "… N more" line (index nil) — ' .. listed)
P.ok(find(cl, '?← p1' .. tag) and not find(cl, '?→ p1' .. tag),
  'decision 8: a sym pending under two edges is one line (latest edge)')
local leaf = S('leaf', 'lib/leaf.go', 1)
gcap:expand(croot, 'callee', { leaf })
gcap:visit(leaf)
cl = render.tree(gcap)
P.ok(find(cl, '? 13 unexplored callees') and find(cl, '? 2 unexplored callers'),
  'decision 8: collapsed counts count unique syms (15 = 13 + 2, not 17)')

-- two back-edges onto the same node from one place read as one line
local fa, fb, fc = S('A', 'x/a.go', 1), S('B', 'x/b.go', 2), S('C', 'x/c.go', 3)
local gb = graph.new(fa)
gb:expand(fa, 'callee', { fb, fc })
gb:visit(fb)
gb:visit(fc)                             -- jump edge fb -> fc
gb:expand(fc, 'impl', { fb })            -- a second, different fact onto fb
local bl = 0
for _, l in ipairs((render.tree(gb))) do
  if l:find('↩ B', 1, true) then bl = bl + 1 end
end
P.eq(bl, 1, 'back-edges onto the same target under one node fold into one ↩ line')

P.done()
