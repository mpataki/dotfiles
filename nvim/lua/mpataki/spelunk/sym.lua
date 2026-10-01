-- SpelunkSym identity, shared by lsp.lua (visit dedupe, children merge) and
-- graph.lua (node keys). One definition, so a visit always matches the node
-- it names; lsp.lua stays graph-free by requiring this instead of graph.lua.
local M = {}

-- path:line:name. `abs` and `col` are not part of identity.
function M.key(sym)
  return sym.path .. ':' .. sym.line .. ':' .. sym.name
end

return M
