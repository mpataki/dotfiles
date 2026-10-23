-- Which tmux pane is the agent. Pure: list-panes rows in, a decision out.
local M = {}

M.FORMAT = '#{pane_id}\t#{session_name}\t#{window_index}\t#{pane_current_command}\t#{pane_current_path}'

function M.parse(out)
  local rows = {}
  for line in (out or ''):gmatch('[^\n]+') do
    local id, session, window, cmd, cwd = line:match('^(%S+)\t(.-)\t(%d+)\t(.-)\t(.*)$')
    if id then
      rows[#rows + 1] = { id = id, session = session, window = window, cmd = cmd, cwd = cwd }
    end
  end
  return rows
end

-- Claude Code sets its process title to its version, so tmux reports e.g.
-- `2.1.309` as the pane command; `claude` covers a launch that has not yet.
function M.is_claude(row)
  return row.cmd == 'claude' or row.cmd:match('^%d+%.%d+%.%d+$') ~= nil
end

function M.label(row)
  return ('%s:%s %s'):format(row.session, row.window, row.id)
end

-- me = { id, session, window }. remembered = a pane id picked earlier.
-- Returns { pane = row } | { pick = rows } | { err = msg }. Tiers: the
-- remembered pane while it is still Claude, then Claude panes in my window,
-- then in my session; the first non-empty tier decides.
function M.choose(rows, me, remembered)
  local claude = vim.tbl_filter(M.is_claude, rows)
  if remembered then
    for _, r in ipairs(claude) do
      if r.id == remembered then return { pane = r } end
    end
  end
  local function tier(pred)
    local t = vim.tbl_filter(pred, claude)
    if #t == 1 then return { pane = t[1] } end
    if #t > 1 then return { pick = t } end
  end
  return tier(function(r) return r.session == me.session and r.window == me.window end)
    or tier(function(r) return r.session == me.session end)
    or { err = ('no Claude pane in tmux session %s'):format(me.session) }
end

return M
