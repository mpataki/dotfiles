-- Ask the agent about code without leaving nvim: <leader>cc on a line or a
-- visual range opens a float; `:w` pastes `path:lines` + the text into the
-- Claude Code pane in this tmux session and submits it. `q` cancels; an empty
-- body sends nothing.
--
-- Transport is tmux, not claudecode.nvim: its IDE websocket carries file/line
-- references only, and its text send needs Claude running inside nvim.
--
-- Target: the pane picked earlier in this nvim while it is still Claude, else
-- the Claude pane in this window, else in this session; several → pick once.
local payload = require('mpataki.ask.payload')
local target = require('mpataki.ask.target')
local tmux = require('mpataki.ask.tmux')
local capture = require('mpataki.review.capture')
local pr = require('mpataki.review.pr')

local M = {}

local remembered -- pane id chosen from a pick; module-local, per nvim

local function notify_err(msg)
  vim.notify('ask: ' .. msg, vim.log.levels.ERROR)
end

-- cb(row) on success; reports and drops the gesture on failure.
function M.resolve(cb)
  local me, err = tmux.me()
  if not me then return notify_err(err) end
  local rows, perr = tmux.panes()
  if not rows then return notify_err(perr) end
  local choice = target.choose(rows, me, remembered)
  if choice.err then return notify_err(choice.err) end
  if choice.pane then return cb(choice.pane) end
  vim.ui.select(choice.pick, { prompt = 'Claude pane', format_item = target.label }, function(row)
    if not row then return end
    remembered = row.id
    cb(row)
  end)
end

-- Fire-and-forget send for other modules (review). cb(ok, err) is optional.
function M.send(text, cb)
  cb = cb or function(ok, err) if not ok then notify_err(err) end end
  M.resolve(function(row)
    local ok, err = tmux.send(row.id, text)
    cb(ok, err, row)
  end)
end

-- opts: command opts (range/line1/line2).
function M.ask(opts)
  local path = vim.api.nvim_buf_get_name(0)
  if path == '' or vim.bo.buftype ~= '' then return notify_err('buffer has no file') end
  local s, e
  if opts and opts.range and opts.range > 0 then
    s, e = opts.line1, opts.line2
  else
    s = vim.api.nvim_win_get_cursor(0)[1]
  end
  local root = pr.root(path)
  M.resolve(function(row)
    local ref = payload.ref(payload.path_for(path, root, row.cwd), s, e)
    capture.open({
      title = ('%s → claude %s'):format(ref, target.label(row)),
      on_save = function(text)
        local body = payload.body(text)
        if body == '' then
          vim.notify('ask: empty, nothing sent')
          return true
        end
        local ok, err = tmux.send(row.id, payload.message(ref, body))
        if not ok then
          notify_err(err)
          return false
        end
        return true
      end,
    })
  end)
end

function M.setup()
  vim.api.nvim_create_user_command('AskClaude', M.ask,
    { range = true, desc = 'Ask Claude about the cursor line / selection' })
  vim.keymap.set('n', '<leader>cc', M.ask, { desc = 'Ask Claude about this line' })
  -- ':' from visual mode supplies the '<,'> range; <Cmd> would not.
  vim.keymap.set('x', '<leader>cc', ':AskClaude<CR>', { silent = true, desc = 'Ask Claude about selection' })
end

return M
