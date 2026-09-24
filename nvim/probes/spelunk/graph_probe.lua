local P = require('probe')
local graph = require('mpataki.spelunk.graph')

-- Random suffix keeps every sym unique to this run.
local tag = tostring(math.random(1e6))
local function S(name, path, line)
  return { name = name .. tag, kind = 12, path = path, line = line, col = 1 }
end

local root = S('NewPod', 'internal/view/pod.go', 50)
local pfi = S('portForwardIndicator', 'internal/view/pod.go', 66)
local rows = S('RowsRange', 'internal/model1/table_data.go', 98)
local fwd = S('IsPodForwarded', 'internal/watch/forwarders.go', 57)
local caller = S('Caller', 'internal/view/browser.go', 10)

P.eq(graph.key(root), 'internal/view/pod.go:50:' .. root.name, 'key is path:line:name')

local g = graph.new(root)
P.eq(graph.key(g:current()), graph.key(root), 'new: root is current')
for _, m in ipairs({ 'expand', 'visit', 'note', 'prune', 'current', 'frontier', 'children', 'serialize' }) do
  P.eq(type(g[m]), 'function', 'api method g:' .. m)
end
P.eq(type(graph.deserialize), 'function', 'api graph.deserialize')

-- expand + idempotency
g:expand(root, 'callee', { pfi, S('Other', 'internal/view/pod.go', 90) })
g:expand(root, 'caller', { caller })
P.eq(#g:children(root), 3, 'expand adds pending children')
P.eq(#g:frontier(), 3, 'frontier lists every pending child')
P.ok(g:has(root) and g:has(pfi) and g:has(caller), 'has: nodes and pending children are known')
P.ok(not g:has(fwd), 'has: a sym never named is unknown')
g:expand(root, 'callee', { pfi, S('Other', 'internal/view/pod.go', 90) })
P.eq(#g:children(root), 3, 'expand idempotent: repeat adds no duplicates')
g:expand(root, 'caller', { pfi })
P.eq(#g:children(root), 4, 'expand keys on (from, edge, child): new edge kind is a new entry')

-- visit: explored
P.eq(g:visit(pfi), 'explored', "visit pending child of current -> 'explored'")
P.eq(graph.key(g:current()), graph.key(pfi), 'explored child becomes current')
local st
for _, c in ipairs(g:children(root)) do
  if graph.key(c.sym) == graph.key(pfi) then st = c.state end
end
P.eq(st, 'explored', 'explored child state flips under its parent')
P.eq(#g:children(root), 3, 'duplicate tree entry (second edge kind) folded out of children')

g:expand(root, 'callee', { pfi })
local tree_entries = 0
for _, c in ipairs(g:children(root)) do
  if graph.key(c.sym) == graph.key(pfi) then
    tree_entries = tree_entries + 1
    P.eq(c.state, 'explored', 'expand after explore does not reset explored state')
  end
end
P.eq(tree_entries, 1, 'expand after explore does not duplicate child')

P.eq(g:visit(pfi), 'noop', "visit current -> 'noop'")

-- visit: jump (unknown)
g:expand(pfi, 'callee', { rows, fwd, S('A', 'internal/x/a.go', 1), S('B', 'internal/x/b.go', 2) })
P.eq(g:visit(fwd), 'explored', 'visit second pending child')
local unknown = S('Grepped', 'internal/y/grep.go', 7)
P.eq(g:visit(unknown), 'jump', "visit unknown sym -> 'jump'")
local jc = g:children(fwd)
P.ok(#jc == 1 and jc[1].edge == 'jump' and jc[1].tree, 'jump: new node under previous current via jump edge')

-- visit: back
local n_unknown = #g:children(unknown)
P.eq(g:visit(root), 'back', "visit an ancestor -> 'back'")
P.eq(#g:children(unknown), n_unknown, 'retreat to an ancestor adds no edge')
P.eq(graph.key(g:current()), graph.key(root), 'back target becomes current')
local before = #g:children(root)
P.eq(g:visit(pfi), 'back', 'walking a tree edge down is still back')
P.eq(#g:children(root), before, 'tree-edge navigation adds no edge')
-- a node in another subtree is a real cross edge
g:visit(root)
local other = S('Other', 'internal/z/other.go', 3)
g:expand(root, 'caller', { other })
P.eq(g:visit(other), 'explored', 'second subtree under root')
P.eq(g:visit(fwd), 'back', "visit existing node in another subtree -> 'back'")
local back_edge
for _, c in ipairs(g:children(other)) do
  if graph.key(c.sym) == graph.key(fwd) and c.back then back_edge = c end
end
P.ok(back_edge ~= nil, 'back: back=true edge from previous current')
P.eq(graph.key(g:current()), graph.key(fwd), 'cross target becomes current')

-- visit: pending child of a non-current node
local g2 = graph.new(root)
g2:expand(root, 'callee', { pfi, fwd })
g2:visit(pfi)
g2:expand(pfi, 'callee', { rows })
g2:visit(root) -- back to root via tree edge
P.eq(g2:visit(rows), 'explored', 'non-current pending: visit reports explored')
local info = g2:info(rows)
P.eq(info and graph.key(info.parent), graph.key(pfi), 'non-current pending: explored under its own parent')
local jump
for _, c in ipairs(g2:children(root)) do
  if graph.key(c.sym) == graph.key(rows) then jump = c end
end
P.ok(jump and jump.edge == 'jump' and jump.state == 'explored', 'non-current pending: jump edge from current')
P.eq(graph.key(g2:current()), graph.key(rows), 'non-current pending: becomes current')

-- loops reported by the LSP are back-edges, not frontier
g2:expand(rows, 'caller', { root })
local loop = g2:children(rows)[1]
P.ok(loop.back and loop.state == 'explored', 'expand to an existing node records a back-edge')
local in_frontier = false
for _, s in ipairs(g2:frontier()) do
  if graph.key(s) == graph.key(root) then in_frontier = true end
end
P.ok(not in_frontier, 'existing node never counts as frontier')

-- note / prune
g2:note(pfi, 'first\nsecond')
P.eq(g2:info(pfi).note, 'first', 'note keeps one line')
g2:note(pfi, 'replaced')
P.eq(g2:info(pfi).note, 'replaced', 'note replaces')
g2:note(pfi, '  ')
P.eq(g2:info(pfi).note, nil, 'blank note clears')
g2:expand(pfi, 'callee', { S('Hidden', 'internal/z/h.go', 3) })
local n0 = #g2:frontier()
g2:prune(pfi)
P.ok(g2:info(pfi).pruned, 'prune sets pruned flag')
P.ok(#g2:frontier() < n0, 'pruned subtree leaves frontier')
P.eq(#g2:children(pfi), 2, 'prune keeps data')
g2:prune(pfi, false)
P.ok(not g2:info(pfi).pruned, 'prune(sym, false) unprunes')

-- serialize is JSON-safe
g2:note(rows, 'n')
local t = vim.json.decode(vim.json.encode(g2:serialize()))
local g3 = graph.deserialize(t)
P.eq(graph.key(g3:current()), graph.key(g2:current()), 'deserialize keeps current')
P.eq(vim.inspect(g3:frontier()), vim.inspect(g2:frontier()), 'deserialize keeps frontier')
P.eq(vim.inspect(g3:children(pfi)), vim.inspect(g2:children(pfi)), 'deserialize keeps children')
P.eq(g3:info(rows).note, 'n', 'deserialize keeps notes')
P.eq(g3:visit(fwd), 'explored', 'deserialized graph keeps working')

-- decision 3: echoes are the same fact drawn twice; dedupe by fact
local function entries(gr, sym, target)
  local out = {}
  for _, c in ipairs(gr:children(sym)) do
    if graph.key(c.sym) == graph.key(target) then out[#out + 1] = c end
  end
  return out
end
local pf, ipf, npod = S('pf', 'a/pod.go', 66), S('ipf', 'a/fwd.go', 57), S('np', 'a/pod.go', 50)
local g4 = graph.new(pf)
g4:expand(pf, 'callee', { ipf })
g4:visit(ipf)
g4:expand(ipf, 'caller', { pf, S('show', 'a/pf.go', 68) })
P.eq(#entries(g4, ipf, pf), 0, 'decision 3: callers naming the tree parent are the same fact as its callee, skipped')
P.eq(#g4:children(ipf), 1, 'decision 3: the rest of the answer still lands')
g4:expand(ipf, 'impl', { ipf })
P.eq(#entries(g4, ipf, ipf), 0, 'decision 3: an entry never points at its own node (child == from)')
g4:visit(pf)
g4:expand(pf, 'caller', { npod })
g4:visit(npod)
g4:expand(npod, 'callee', { pf })
P.eq(#entries(g4, npod, pf), 0, 'decision 3: callee answer naming the node you came up from is skipped')
local g5 = graph.deserialize(vim.json.decode(vim.json.encode(g4:serialize())))
g5:expand(ipf, 'caller', { pf })
P.eq(#entries(g5, ipf, pf), 0, 'decision 3: facts survive serialize/deserialize')

-- the dispatch case: run's callers and callees both name exec — two facts
local run, exec = S('run', 'v/command.go', 141), S('exec', 'v/command.go', 298)
local gd = graph.new(run)
gd:expand(run, 'caller', { exec, S('goto', 'v/app.go', 693) })
gd:expand(run, 'callee', { exec, S('inject', 'v/app.go', 700) })
P.eq(#entries(gd, run, exec), 2, 'decision 3: run->exec and exec->run are two facts, both kept')
gd:visit(exec)
local tree = entries(gd, run, exec)
P.ok(#tree == 1 and tree[1].tree, 'decision 3: exec has one tree line under run')
local cyc = entries(gd, exec, run)
P.ok(#cyc == 1 and cyc[1].back and cyc[1].edge == 'callee',
  'decision 3: exec->run (from run\'s callers) moves under exec as a back-edge')
gd:expand(exec, 'callee', { run, S('Init', 'v/types.go', 57) })
P.eq(#entries(gd, exec, run), 1, 'decision 3: exec\'s callees naming run add no second line')

-- decision 6: glyph from the edge actually walked (most recent expand wins)
P.eq(tree[1].edge, 'callee', 'decision 6: visit walks the most recent pending entry (callee over caller)')
local g6 = graph.new(run)
g6:expand(run, 'callee', { exec })
g6:expand(run, 'caller', { exec })
g6 = graph.deserialize(vim.json.decode(vim.json.encode(g6:serialize())))
g6:visit(exec)
P.eq(entries(g6, run, exec)[1].edge, 'caller', 'decision 6: pending stamps survive serialize/deserialize')

-- decision 7: the asked-about symbol enters as def, not jump
local inject, init = S('inject', 'v/app.go', 700), S('Init', 'm/types.go', 57)
local g7 = graph.new(inject)
g7:expand(init, 'impl', { S('BInit', 'v/browser.go', 61) })
local asked = entries(g7, inject, init)
P.ok(#asked == 1 and asked[1].edge == 'def' and asked[1].tree,
  'decision 7: expand from a non-node adds it under current as def')
P.eq(graph.key(g7:current()), graph.key(init), 'decision 7: the asked-about sym becomes current')
P.eq(#g7:children(init), 1, 'decision 7: the answer hangs off the asked-about sym')

P.done()
