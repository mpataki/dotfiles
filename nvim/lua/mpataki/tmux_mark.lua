-- The tmux pane marked with prefix m. tmux.conf keeps our own mark in the
-- global @mark option (a pane id) instead of tmux's built-in mark, whose
-- forced border styling can't be turned off. Falls back to the built-in mark
-- so a pane marked from the right-click menu still works.
local M = {}

local function tmux(args)
  local out = vim.fn.system(vim.list_extend({ 'tmux' }, args))
  return vim.v.shell_error == 0 and vim.trim(out) or nil
end

-- Returns the marked pane id (e.g. "%12"), or nil when nothing live is marked.
function M.pane()
  local id = tmux({ 'show', '-gv', '@mark' })
  -- A pane killed while marked leaves its id behind; tmux never reuses ids,
  -- so a failed lookup means the mark is stale.
  if id and id ~= '' and tmux({ 'display', '-p', '-t', id, '#{pane_id}' }) == id then
    return id
  end
  local native = tmux({ 'list-panes', '-a', '-F', '#{?pane_marked,#{pane_id},}' })
  return native and native ~= '' and native or nil
end

return M
