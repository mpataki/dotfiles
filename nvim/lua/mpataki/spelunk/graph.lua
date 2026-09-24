-- The dive as a graph: nodes (symbols you have stood on), per-node child entries
-- (what the LSP said is adjacent), the current node, notes and prune flags. Pure
-- data — no vim.lsp, no buffers — so render and the probes drive it directly.
--
-- Invariants the rest of the module leans on:
--   * every non-root node has a tree entry (explored, not back) in its parent's
--     list; the earliest-`at` one is the tree edge render walks. Other entries
--     between the same pair are either same-direction duplicates (folded out
--     of children()) or run the other way and live under the child instead
--     (see facts).
--   * an entry whose target is already a node is never 'unexplored'. Targets that
--     become nodes later are swept: under the tree parent they are duplicates,
--     anywhere else they turn into back-edges (the LSP told us about a loop).
--   * entries get `at` (a global sequence number) when they become explored, so
--     sorting by it replays first-visit order; pending entries get `born` at
--     creation, so the most recent expand is the one a visit walks.
--   * facts: a caller/callee/def/impl entry is one directed code relation
--     (`call|<caller>|<callee>`, `def|<from>|<to>`, `impl|<from>|<to>`), and no
--     two entries anywhere hold the same fact: B's callers naming A is the
--     same fact as A's callees naming B, and is dropped at expand. No entry
--     points at its own node. `_facts` is derived from the entries.
local M = {}

local Graph = {}
Graph.__index = Graph

function M.key(sym)
  return sym.path .. ':' .. sym.line .. ':' .. sym.name
end

local function copy_sym(s)
  return { name = s.name, kind = s.kind, path = s.path, line = s.line, col = s.col }
end

local function tick(self)
  self._seq = self._seq + 1
  return self._seq
end

-- nil for 'jump': navigation is not a code relation.
local function fact(from, edge, to)
  if edge == 'caller' then return 'call|' .. to .. '|' .. from end
  if edge == 'callee' then return 'call|' .. from .. '|' .. to end
  if edge == 'def' or edge == 'impl' then return edge .. '|' .. from .. '|' .. to end
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

-- The entry render descends through from parent to its tree child k.
local function tree_entry(self, parent, k)
  local best
  for _, e in ipairs(self._kids[parent]) do
    if e.key == k and e.state == 'explored' and not e.back and (not best or e.at < best.at) then
      best = e
    end
  end
  return best
end

local FLIP = { caller = 'callee', callee = 'caller' }

local function up(edge) return edge == 'caller' end

-- A call entry between parent and its tree child k that runs against the tree
-- edge (run's callers naming exec, when exec is run's callee) is a different
-- fact the tree does not show: move it under the child, flipped, as a
-- back-edge (exec's callee run). Same-direction duplicates stay and fold out.
local function settle(self, parent, k)
  local tree = tree_entry(self, parent, k)
  if not tree then return end
  local list, keep = self._kids[parent], {}
  for _, e in ipairs(list) do
    if e.key == k and e ~= tree and e.state == 'explored' and FLIP[e.edge] and up(e.edge) ~= up(tree.edge) then
      local kids = self._kids[k]
      kids[#kids + 1] = { key = parent, sym = copy_sym(self._nodes[parent].sym), edge = FLIP[e.edge],
        count = e.count, state = 'explored', back = true, at = tick(self), born = e.born }
    else
      keep[#keep + 1] = e
    end
  end
  self._kids[parent] = keep
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

local function walk(self, fn, k)
  k = k or self._root
  if fn(k) == false then return end
  for _, e in ipairs(tree_kids(self, k)) do walk(self, fn, e.key) end
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
      if n and n.parent == fk then settle(self, fk, ck) end
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

local function sweep(self, k, parent)
  for from, list in pairs(self._kids) do
    for _, e in ipairs(list) do
      if e.key == k and e.state == 'unexplored' then
        e.state, e.back, e.at = 'explored', from ~= parent, tick(self)
      end
    end
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
    if not related(self, prev, k) and not find_entry(self._kids[prev], k) then
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

  add_node(self, sym, parent)
  if result == 'jump' then
    local list = self._kids[prev]
    list[#list + 1] = explored_entry(self, k, sym, 'jump', false)
  else
    local tree = latest_pending(self._kids[parent], k)
    tree.state, tree.back, tree.at = 'explored', false, tick(self)
    if parent ~= prev then
      local list = self._kids[prev]
      list[#list + 1] = explored_entry(self, k, sym, 'jump', false)
    end
  end
  sweep(self, k, parent)
  settle(self, parent, k)
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

function Graph:root()
  return copy_sym(self._nodes[self._root].sym)
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
  return { version = 1, root = self._root, current = self._cur, seq = self._seq,
    nodes = nodes, notes = notes }
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
  self._root, self._cur = t.root, t.current
  return self
end

return M
