-- Shared driver for the spelunk scenarios: narrated dives through ~/code/k9s
-- that act like a human at the keyboard (vim.lsp.buf.*, :cc on a quickfix
-- entry, <C-o>, :edit) and dump what spelunk shows. Not a probe: nothing here
-- asserts. A scenario that errors never reaches P.done(), so run.sh sees no
-- summary line and fails it.
--
-- Headless traps this works around (see session_probe.lua):
--   * CursorMoved never fires while vim.wait pumps, so every programmatic
--     cursor move fires it by hand.
--   * gopls answers call hierarchy only once the workspace is loaded: poll
--     prepareCallHierarchy before the first step.
--   * cursor goes on the *name*, never the receiver.
local P = require('probe')

local D = {}

D.K9S = vim.fn.expand('~/code/k9s')
D.OUT = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h') .. '/out'

local spelunk = require('mpataki.spelunk')
local lsp = require('mpataki.spelunk.lsp')
local SETTLE = lsp.DEBOUNCE_MS * 4 + 400

local name
local n = 0

-- Straight to stdout: headless print() runs messages together without a
-- separator often enough to garble the log.
local function say(line)
  io.stdout:write(line, '\n')
end

local function where(sym)
  if not sym then return '<none>' end
  return ('%s@%s:%d'):format(sym.name, sym.path, sym.line)
end

-- Graph signature through the public surface: serialize() is plain data.
local function sig()
  local g = spelunk.graph()
  return g and vim.json.encode(g:serialize()) or ''
end

local function qf_state()
  local q = vim.fn.getqflist({ id = 0, changedtick = 0 })
  return q.id .. ':' .. q.changedtick
end

local function pos_state()
  local c = vim.api.nvim_win_get_cursor(0)
  return vim.api.nvim_get_current_buf() .. ':' .. c[1] .. ':' .. c[2]
end

-- Wait until the graph stops changing: responses that resolve many locations
-- (references across files) emit their expand after a documentSymbol per file.
local function stabilize()
  local last, quiet = sig(), 0
  for _ = 1, 40 do
    P.wait(300)
    local now = sig()
    if now == last then quiet = quiet + 1 else quiet, last = 0, now end
    if quiet >= 4 then return end
  end
end

-- The human moved the cursor: fire what the event loop would have.
local function moved()
  if vim.bo.buftype ~= '' then return end
  vim.api.nvim_exec_autocmds('CursorMoved', { buffer = vim.api.nvim_get_current_buf() })
  P.wait(SETTLE)
  stabilize()
end

function D.begin(scenario)
  name = scenario
  if vim.fn.isdirectory(D.K9S) == 0 then error('corpus missing: ' .. D.K9S) end
  vim.cmd.cd(D.K9S)
  vim.fn.mkdir(D.OUT, 'p')
  spelunk.setup({ export_dir = D.OUT })
  say('=== ' .. name .. ' (k9s ' .. vim.trim(vim.fn.system({ 'git', '-C', D.K9S, 'rev-parse', '--short', 'HEAD' })) .. ')')
end

-- Column (0-based) of the `()` capture in `pat` on buffer line `line`.
local function col_of(line, pat)
  local text = vim.api.nvim_buf_get_lines(0, line - 1, line, false)[1] or ''
  local c = text:match(pat)
  if not c then error(('pattern %q not on line %d: %s'):format(pat, line, text)) end
  return c - 1
end

-- :edit (when needed) and put the cursor on `pat`'s capture, like a human
-- opening the file from the error message.
function D.go(file, line, pat)
  vim.cmd("normal! m'")
  if vim.fs.normalize(vim.api.nvim_buf_get_name(0)) ~= vim.fs.normalize(D.K9S .. '/' .. file) then
    vim.cmd.edit(vim.fn.fnameescape(file))
  end
  vim.api.nvim_win_set_cursor(0, { line, pat and col_of(line, pat) or 0 })
  moved()
end

-- Same buffer, cursor onto `pat` on `line` (reading the code, then aiming gd).
function D.aim(line, pat)
  vim.api.nvim_win_set_cursor(0, { line, pat and col_of(line, pat) or 0 })
  moved()
end

function D.ready()
  local buf = vim.api.nvim_get_current_buf()
  local c
  P.wait(30000, function()
    c = vim.lsp.get_clients({ bufnr = buf, name = 'gopls' })[1]
    return c ~= nil
  end)
  if not c then error('gopls never attached') end
  local cur = vim.api.nvim_win_get_cursor(0)
  local params = vim.lsp.util.make_position_params(0, c.offset_encoding)
  for _ = 1, 45 do
    local r = c:request_sync('textDocument/prepareCallHierarchy', params, 5000, buf)
    if r and r.result and #r.result > 0 then return end
    P.wait(2000)
  end
  error('gopls workspace never ready at ' .. vim.api.nvim_buf_get_name(buf) .. ':' .. cur[1])
end

-- Issue an LSP command the way the keymap would and wait for its effect:
-- a quickfix list, a jump, or a graph change. Returns the quickfix items when
-- the command filled one (nil for a direct jump or nothing).
function D.ask(fn)
  local s, q, p = sig(), qf_state(), pos_state()
  fn()
  P.wait(20000, function() return sig() ~= s or qf_state() ~= q or pos_state() ~= p end)
  local filled = qf_state() ~= q
  P.wait(SETTLE)
  stabilize()
  if filled then
    -- copen took focus; the human reads the list, then goes back to the code.
    vim.cmd('wincmd p')
    local items = vim.fn.getqflist()
    say(('   quickfix: %d entries'):format(#items))
    for i, it in ipairs(items) do
      if i > 12 then say('     …') break end
      say(('     %2d %s:%d  %s'):format(i, vim.fn.fnamemodify(vim.fn.bufname(it.bufnr), ':.'), it.lnum,
        vim.trim(it.text)))
    end
    return items
  end
  vim.cmd('cclose')
  if pos_state() ~= p then say('   jumped to ' .. vim.fn.expand('%:.') .. ':' .. vim.fn.line('.')) end
  if sig() == s and not filled and pos_state() == p then say('   (no response / no graph change)') end
  moved()
end

-- "The user picked entry N": :cc N from the quickfix list the builtin filled,
-- exactly what <CR> in the quickfix window does. `pred(item, file)` picks the
-- first match; falls back to entry 1 and says so.
function D.pick(items, pred, why)
  if not items or #items == 0 then
    say('   DEVIATION: empty quickfix; cannot pick ' .. (why or '?'))
    return false
  end
  local idx
  for i, it in ipairs(items or {}) do
    if pred(it, vim.fn.fnamemodify(vim.fn.bufname(it.bufnr), ':.')) then idx = i break end
  end
  if not idx then
    say('   DEVIATION: no quickfix entry for ' .. (why or '?') .. '; taking entry 1')
    idx = 1
  end
  vim.cmd('cc ' .. idx)
  vim.cmd('cclose')
  say(('   picked %d → %s:%d'):format(idx, vim.fn.expand('%:.'), vim.fn.line('.')))
  moved()
  return true
end

-- <C-o>: back through the jumplist.
function D.back()
  vim.cmd('execute "normal! \\<C-o>"')
  say('   <C-o> → ' .. vim.fn.expand('%:.') .. ':' .. vim.fn.line('.'))
  moved()
end

function D.note(text)
  vim.cmd('SpelunkNote ' .. text)
end

function D.step(intent)
  n = n + 1
  local g = spelunk.graph()
  say(('step %d %s: current=%s frontier=%s'):format(n, intent, where(g and g:current()),
    g and #g:frontier() or '-'))
end

local function write(path, lines)
  if vim.fn.writefile(lines, path) ~= 0 then error('cannot write ' .. path) end
end

-- :SpelunkOpen, dump the split to out/<name>.tree.txt and stdout, and put the
-- export at out/<name>.md (auto-started sessions are named <root>-<HHMM>).
function D.finish()
  vim.cmd('cclose')
  if not spelunk.graph() then error('no session at the end of ' .. name) end
  vim.cmd('SpelunkOpen')
  local lines
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local b = vim.api.nvim_win_get_buf(w)
    if vim.bo[b].filetype == 'spelunk' then lines = vim.api.nvim_buf_get_lines(b, 0, -1, false) end
  end
  if not lines then error('SpelunkOpen showed no split') end
  write(D.OUT .. '/' .. name .. '.tree.txt', lines)
  say('=== ' .. name .. ' tree (session ' .. spelunk.name() .. ')')
  for _, l in ipairs(lines) do say(l) end
  say('=== end ' .. name)
  spelunk.export()
  local src, dst = spelunk.export_path(), D.OUT .. '/' .. name .. '.md'
  if src ~= dst then
    local ok, err = os.rename(src, dst)
    if not ok then error('export move failed: ' .. tostring(err)) end
  end
  P.done()
end

return D
