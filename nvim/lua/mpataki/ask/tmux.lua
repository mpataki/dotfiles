-- The tmux side: who am I, which panes exist, paste into one. Thin IO only;
-- decisions live in target.lua. M.argv is the base command so probes can aim
-- at a private server (`tmux -L <name>`) instead of the live one.
local target = require('mpataki.ask.target')

local M = {}

M.argv = { 'tmux' }
M.TIMEOUT = 3000
local BUFFER = 'mpataki-ask'

local function run(args, stdin)
  local argv = vim.list_extend(vim.deepcopy(M.argv), args)
  local ok, obj = pcall(function()
    return vim.system(argv, { text = true, stdin = stdin }):wait(M.TIMEOUT)
  end)
  if not ok then return nil, tostring(obj) end
  if obj.code ~= 0 then
    local first = vim.trim(obj.stderr or ''):match('^[^\n]*')
    return nil, first ~= '' and first or ('tmux exited ' .. tostring(obj.code))
  end
  return obj.stdout
end

function M.me()
  if not vim.env.TMUX or not vim.env.TMUX_PANE then return nil, 'not inside tmux' end
  local out, err = run({ 'display-message', '-p', '-t', vim.env.TMUX_PANE, target.FORMAT })
  if not out then return nil, err end
  local row = target.parse(out)[1]
  if not row then return nil, 'tmux: could not read own pane' end
  return row
end

function M.panes()
  local out, err = run({ 'list-panes', '-a', '-F', target.FORMAT })
  if not out then return nil, err end
  return target.parse(out)
end

-- Bracketed paste (-p): the agent's TUI takes the newlines in `text` as text,
-- so the one Enter after it is the only submit.
function M.send(pane_id, text)
  local _, err = run({ 'load-buffer', '-b', BUFFER, '-' }, text)
  if err then return false, err end
  _, err = run({ 'paste-buffer', '-p', '-d', '-b', BUFFER, '-t', pane_id })
  if err then return false, err end
  _, err = run({ 'send-keys', '-t', pane_id, 'Enter' })
  if err then return false, err end
  return true
end

return M
