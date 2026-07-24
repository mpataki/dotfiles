-- Headless probe harness for validating Neovim config changes.
--
-- Run a probe script against the full, real config:
--   nvim --headless -c 'luafile path/to/probe.lua' -c 'qa'
--
-- Use `luafile` via -c, NOT `nvim -l`: -c runs *post*-startup, so lazy.nvim's
-- on-demand `require` hook is live and plugins load when the probe touches them.
-- `nvim -l` runs too early — `require('telescope')` fails because lazy hasn't
-- wired it yet.
--
-- In a probe script:
--   local P = require('probe')
--   P.eq(P.select(2), 42, 'answer')
--   P.done()   -- summary + non-zero exit if any check failed
local P = { _pass = 0, _fail = 0 }

local function record(ok, msg)
  if ok then P._pass = P._pass + 1 else P._fail = P._fail + 1 end
  print(('%s %s'):format(ok and 'PASS' or 'FAIL', msg or ''))
end

-- Assert a truthy condition.
function P.ok(cond, msg)
  local ok = cond and true or false
  record(ok, msg)
  return ok
end

-- Assert equality; on failure prints both sides.
function P.eq(got, want, msg)
  local ok = got == want
  record(ok, (msg or '') .. (ok and '' or
    (' — got ' .. vim.inspect(got) .. ', want ' .. vim.inspect(want))))
  return ok
end

-- Pump the event loop so async work (telescope finders, LSP, jobs) runs.
-- Without `pred`, waits the full `ms`; with it, returns as soon as it's true.
function P.wait(ms, pred)
  vim.wait(ms or 2000, pred or function() return false end)
end

-- The current telescope picker, after opening one and P.wait()-ing.
-- Returns (picker, live_result_count) or nil when no picker is open.
function P.picker()
  local ok, state = pcall(require, 'telescope.actions.state')
  if not ok then return nil end
  local p = state.get_current_picker(vim.api.nvim_get_current_buf())
  if not p then return nil end
  return p, (p.manager and p.manager:num_results() or -1)
end

-- LSP/diagnostic entries for a buffer (0 = current).
function P.diagnostics(buf)
  return vim.diagnostic.get(buf or 0)
end

-- Captured :messages output (for asserting notifications/errors).
function P.messages()
  return vim.api.nvim_exec2('messages', { output = true }).output
end

-- Finish: print a summary and exit. Non-zero (`:cquit`) if anything failed, so
-- the calling shell or agent sees the verdict. Always call this last.
function P.done()
  print(('probe: %d passed, %d failed'):format(P._pass, P._fail))
  if P._fail > 0 then
    vim.cmd('cquit ' .. P._fail)
  else
    vim.cmd('qall!')
  end
end

return P
