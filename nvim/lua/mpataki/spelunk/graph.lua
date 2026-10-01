-- The dive as a graph: nodes (symbols you have stood on), per-node child entries
-- (what the LSP said is adjacent), the current node, notes and prune flags. Pure
-- data — no vim.lsp, no buffers — so render and the probes drive it directly.
--
-- Invariants the rest of the module leans on:
--   * nesting is one direction: an explored entry under A pointing at B means A
--     calls, uses or implements-toward B (or you jumped A -> B). 'caller'
--     entries are only ever pending; once the caller is a node the entry lives
--     under the caller as a 'callee' instead. So walking a caller puts it above
--     the node that named it: in that node's place when it is a root, else as a
--     new root of its own (the dive is a forest, `_roots` in order).
--   * every non-root node has a tree entry (explored, not back) in its parent's
--     list; the earliest-`at` one is the tree edge render walks. Other entries
--     between the same pair are same-direction duplicates, folded out of
--     children().
--   * an entry whose target is already a node is never 'unexplored'. Targets that
--     become nodes later are swept: under the tree parent they are duplicates,
--     anywhere else they turn into back-edges (the LSP told us about a loop).
--   * entries get `at` (a global sequence number) when they become explored, so
--     sorting by it replays first-visit order; pending entries get `born` at
--     creation, so the most recent expand is the one a visit walks.
--   * facts: a caller/callee/def/impl entry is one code relation
--     (`call|<caller>|<callee>`, `impl|<a>|<b>` with a < b), and no two entries
--     anywhere hold the same fact: B's callers naming A is the same fact as A's
--     callees naming B, gd on B from inside A is the same fact as A calling B,
--     and gi answered from either side of an interface is the same fact. Each
--     is dropped at expand. No entry points at its own node. `_facts` is
--     derived from the entries.
local M = {}

local Graph = {}
Graph.__index = Graph

function M.key(sym)
  return sym.path .. ':' .. sym.line .. ':' .. sym.name
end

local function copy_sym(s)
  return { name = s.name, kind = s.kind, path = s.path, line = s.line, col = s.col, abs = s.abs }
end

local function tick(self)
  self._seq = self._seq + 1
  return self._seq
end

-- nil for 'jump': navigation is not a code relation.
local function fact(from, edge, to)
  if edge == 'caller' then return 'call|' .. to .. '|' .. from end
  if edge == 'callee' or edge == 'def' then return 'call|' .. from .. '|' .. to end
  if edge == 'impl' then
    if to < from then from, to = to, from end
    return 'impl|' .. from .. '|' .. to
  end
end

local function record(self, from, e)
  local f = fact(from, e.edge, e.key)
  if f then self._facts[f] = true end
end

local function add_node(self, sym, parent)
  local k = M.key(sym)
  self._nodes[k] = { sym = copy_sym(sym), parent = parent, pruned = false, order = tick(self) }
  self._kids[k] = self._kids[k] or {}
  return k
end

function M.new(root)
  local self = setmetatable({ _nodes = {}, _kids = {}, _notes = {}, _facts = {}, _seq = 0 }, Graph)
  self._root = add_node(self, root, nil)
  self._roots = { self._root }
  self._cur = self._root
  return self
end

local function find_entry(list, k, edge)
  for _, e in ipairs(list) do
    if e.key == k and (edge == nil or e.edge == edge) then return e end
  end
end

local function explored_entry(self, k, sym, edge, back)
  local now = tick(self)
  return { key = k, sym = copy_sym(sym), edge = edge, count = 1,
    state = 'explored', back = back, at = now, born = now }
end

-- Caller `from` calls node `to`: the explored, downward form of a caller entry.
local function add_down(self, from, to, count, born, back)
  local e = explored_entry(self, to, self._nodes[to].sym, 'callee', back)
  e.count, e.born = count or 1, born or e.born
  local list = self._kids[from]
  list[#list + 1] = e
  return e
end

-- The pending entry for k a visit walks: the most recently born one.
local function latest_pending(list, k)
  local best
  for _, e in ipairs(list) do
    if e.key == k and e.state == 'unexplored' and (not best or (e.born or 0) > (best.born or 0)) then
      best = e
    end
  end
  return best
end

-- Tree children in first-visit order, for DFS walks.
local function tree_kids(self, k)
  local out = {}
  for _, e in ipairs(self._kids[k]) do
    local n = self._nodes[e.key]
    if e.state == 'explored' and not e.back and n and n.parent == k then
      out[#out + 1] = e
    end
  end
  table.sort(out, function(a, b) return a.at < b.at end)
  local seen, uniq = {}, {}
  for _, e in ipairs(out) do
    if not seen[e.key] then
      seen[e.key] = true
      uniq[#uniq + 1] = e
    end
  end
  return uniq
end

-- DFS over every root in order; fn returning false skips that subtree.
local function walk(self, fn)
  local function go(k)
    if fn(k) == false then return end
    for _, e in ipairs(tree_kids(self, k)) do go(e.key) end
  end
  for _, r in ipairs(self._roots) do go(r) end
end

-- Asking the LSP about a symbol that is not yet a node means you were reading
-- it from the current node: it enters as a 'def' child of current (the thing
-- you asked about) and becomes current, so the children have a parent.
function Graph:expand(from, edge, children)
  local fk = M.key(from)
  if not self._nodes[fk] then
    self:expand(self._nodes[self._cur].sym, 'def', { from })
    self:visit(from)
  end
  for _, c in ipairs(children or {}) do
    local ck = M.key(c)
    local e = ck ~= fk and find_entry(self._kids[fk], ck, edge)
    if e then
      e.count = math.max(e.count, c.count or 1)
    elseif ck ~= fk and not self._facts[fact(fk, edge, ck)] then
      local n = self._nodes[ck]
      if n and edge == 'caller' then
        -- A caller that is already a node: the call hangs under it, pointing down.
        record(self, ck, add_down(self, ck, fk, c.count, nil, self._nodes[fk].parent ~= ck))
      else
        if n then
          e = explored_entry(self, ck, c, edge, n.parent ~= fk)
        else
          e = { key = ck, sym = copy_sym(c), edge = edge, state = 'unexplored', back = false,
            born = tick(self) }
        end
        e.count = c.count or 1
        local list = self._kids[fk]
        list[#list + 1] = e
        record(self, fk, e)
      end
    end
  end
end

local function is_ancestor(self, a, b)
  local p = self._nodes[b].parent
  while p do
    if p == a then return true end
    p = self._nodes[p].parent
  end
  return false
end

-- Same root-to-leaf path: one is an ancestor of the other.
local function related(self, a, b)
  return is_ancestor(self, a, b) or is_ancestor(self, b, a)
end

-- First node, DFS order, holding a pending entry for k.
local function pending_parent(self, k)
  local found
  walk(self, function(nk)
    if found then return false end
    if latest_pending(self._kids[nk], k) then found = nk; return false end
  end)
  return found
end

local function remove(list, e)
  for i, x in ipairs(list) do
    if x == e then return table.remove(list, i) end
  end
end

-- Walking caller entry `e` (under node x) to new node k puts k above x: in x's
-- place when x is a root, else as a new root with x a back-edge under it.
local function lift(self, x, k, sym, e)
  remove(self._kids[x], e)
  add_node(self, sym, nil)
  local xn = self._nodes[x]
  if xn.parent == nil then
    xn.parent = k
    for i, r in ipairs(self._roots) do
      if r == x then self._roots[i] = k end
    end
    add_down(self, k, x, e.count, e.born, false)
  else
    self._roots[#self._roots + 1] = k
    add_down(self, k, x, e.count, e.born, true)
  end
end

-- Other pending entries for the new node k turn explored: back-edges unless
-- under k's tree parent. Pending callers of k's neighbours move under k.
local function sweep(self, k)
  local parent = self._nodes[k].parent
  for from, list in pairs(self._kids) do
    local keep = {}
    for _, e in ipairs(list) do
      if e.key == k and e.state == 'unexplored' and e.edge == 'caller' then
        add_down(self, k, from, e.count, e.born, self._nodes[from].parent ~= k)
      else
        if e.key == k and e.state == 'unexplored' then
          e.state, e.back, e.at = 'explored', from ~= parent, tick(self)
        end
        keep[#keep + 1] = e
      end
    end
    self._kids[from] = keep
  end
end

function Graph:visit(sym)
  local k = M.key(sym)
  local prev = self._cur
  if k == prev then return 'noop' end

  if self._nodes[k] then
    -- Retreating up your own path (<C-o> to any ancestor) or going back down
    -- it is navigation, not a loop; it adds no edge. Loops the code itself
    -- forms are already caught at expand time. Only landing in another
    -- subtree draws a cross edge.
    if not related(self, prev, k) and not find_entry(self._kids[prev], k)
      and not find_entry(self._kids[k], prev) then
      local list = self._kids[prev]
      list[#list + 1] = explored_entry(self, k, sym, 'jump', true)
    end
    self._cur = k
    return 'back'
  end

  local parent, result = prev, 'jump'
  if latest_pending(self._kids[prev], k) then
    result = 'explored'
  else
    local elsewhere = pending_parent(self, k)
    if elsewhere then parent, result = elsewhere, 'explored' end
  end

  if result == 'jump' then
    add_node(self, sym, prev)
    local list = self._kids[prev]
    list[#list + 1] = explored_entry(self, k, sym, 'jump', false)
  else
    local tree = latest_pending(self._kids[parent], k)
    if tree.edge == 'caller' then
      lift(self, parent, k, sym, tree)
    else
      add_node(self, sym, parent)
      tree.state, tree.back, tree.at = 'explored', false, tick(self)
    end
    if parent ~= prev then
      local list = self._kids[prev]
      list[#list + 1] = explored_entry(self, k, sym, 'jump', false)
    end
  end
  sweep(self, k)
  self._cur = k
  return result
end

-- One line per sym; empty text clears. Any sym may carry a note, but only
-- nodes render one.
function Graph:note(sym, text)
  local line = vim.trim((text or ''):match('^[^\n]*'))
  self._notes[M.key(sym)] = line ~= '' and line or nil
end

-- `on` defaults to true; pass false to unprune.
function Graph:prune(sym, on)
  local n = self._nodes[M.key(sym)]
  if n then n.pruned = on ~= false end
end

function Graph:current()
  return copy_sym(self._nodes[self._cur].sym)
end

-- The sym the session started at, which may no longer be a root: walking its
-- callers puts them above it.
function Graph:root()
  return copy_sym(self._nodes[self._root].sym)
end

-- Tops of the forest, in order. Render draws one tree per root.
function Graph:roots()
  local out = {}
  for _, k in ipairs(self._roots) do out[#out + 1] = copy_sym(self._nodes[k].sym) end
  return out
end

-- nil for a sym that is not a node.
function Graph:info(sym)
  local n = self._nodes[M.key(sym)]
  if not n then return nil end
  return {
    note = self._notes[M.key(sym)],
    pruned = n.pruned,
    parent = n.parent and copy_sym(self._nodes[n.parent].sym) or nil,
  }
end

-- Known = a node, or named as a child anywhere (pending, pruned or not). What
-- lsp's visit detection asks before counting a same-buffer move as a jump.
function Graph:has(sym)
  local k = M.key(sym)
  if self._nodes[k] then return true end
  for _, list in pairs(self._kids) do
    if find_entry(list, k) then return true end
  end
  return false
end

-- Unexplored children, DFS order, one per sym. Pruned subtrees are skipped:
-- pruning is how you tell the frontier you are not going there.
function Graph:frontier()
  local out, seen = {}, {}
  walk(self, function(k)
    if self._nodes[k].pruned then return false end
    for _, e in ipairs(self._kids[k]) do
      if e.state == 'unexplored' and not seen[e.key] then
        seen[e.key] = true
        out[#out + 1] = copy_sym(e.sym)
      end
    end
  end)
  return out
end

-- Explored entries in first-visit order, then unexplored in the order the LSP
-- reported them. `tree` marks the edge render descends through; duplicate tree
-- entries (same child under a second edge kind) are omitted.
function Graph:children(sym)
  local k = M.key(sym)
  local list = self._kids[k]
  if not list then return {} end
  local explored, pending, seen_tree = {}, {}, {}
  for _, e in ipairs(list) do
    if e.state == 'explored' then explored[#explored + 1] = e else pending[#pending + 1] = e end
  end
  table.sort(explored, function(a, b) return a.at < b.at end)
  local out = {}
  local function push(e, tree)
    out[#out + 1] = { sym = copy_sym(e.sym), edge = e.edge, state = e.state,
      back = e.back, tree = tree, count = e.count }
  end
  for _, e in ipairs(explored) do
    local n = self._nodes[e.key]
    local tree = not e.back and n ~= nil and n.parent == k
    if tree then
      if not seen_tree[e.key] then
        seen_tree[e.key] = true
        push(e, true)
      end
    else
      push(e, false)
    end
  end
  for _, e in ipairs(pending) do push(e, false) end
  return out
end

-- Node records in creation order, each with its entries in list order: plain
-- arrays and string keys only, so vim.json round-trips it.
function Graph:serialize()
  local nodes = {}
  for k, n in pairs(self._nodes) do
    local entries = {}
    for _, e in ipairs(self._kids[k]) do
      entries[#entries + 1] = { key = e.key, sym = copy_sym(e.sym), edge = e.edge,
        count = e.count, state = e.state, back = e.back, at = e.at, born = e.born }
    end
    nodes[#nodes + 1] = { key = k, sym = copy_sym(n.sym), parent = n.parent,
      pruned = n.pruned, order = n.order, entries = entries }
  end
  table.sort(nodes, function(a, b) return a.order < b.order end)
  local notes = {}
  for k, text in pairs(self._notes) do notes[#notes + 1] = { key = k, text = text } end
  table.sort(notes, function(a, b) return a.key < b.key end)
  return { version = 2, root = self._root, roots = vim.list_extend({}, self._roots),
    current = self._cur, seq = self._seq, nodes = nodes, notes = notes }
end

function M.deserialize(t)
  local self = setmetatable({ _nodes = {}, _kids = {}, _notes = {}, _facts = {}, _seq = t.seq or 0 }, Graph)
  for _, n in ipairs(t.nodes or {}) do
    self._nodes[n.key] = { sym = copy_sym(n.sym), parent = n.parent,
      pruned = n.pruned == true, order = n.order }
    local list = {}
    for _, e in ipairs(n.entries or {}) do
      -- Sessions saved before `born` existed: 0 lets list order break ties.
      list[#list + 1] = { key = e.key, sym = copy_sym(e.sym), edge = e.edge,
        count = e.count or 1, state = e.state, back = e.back == true, at = e.at, born = e.born or 0 }
      record(self, n.key, list[#list])
    end
    self._kids[n.key] = list
  end
  for _, n in ipairs(t.notes or {}) do self._notes[n.key] = n.text end
  -- Version 1 had one root and no forest.
  self._root, self._cur = t.root, t.current
  self._roots = t.roots or { t.root }
  return self
end

return M
