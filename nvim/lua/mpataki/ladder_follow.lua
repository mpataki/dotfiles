-- Keeps a <leader>gp ladder view on its branch's latest head. The review
-- worktree stays detached on purpose: git refuses to rebase or move a branch
-- checked out in another worktree, and cascades must always move rungs. So
-- "following" a rung means re-detaching at its new tip whenever it moves.
--
-- Event-driven: git's reference-transaction hook (bin/ladder-notify, wired in
-- git/gitconfig) calls poke() on every branch move in a ladder repo, from any
-- worktree. FocusGained is the backstop for anything the hook misses.
--
-- Stops when HEAD moves away from the followed commit by any other means
-- (manual checkout, a new pick, attaching a branch), or on stop() (<leader>gt,
-- HEAD/attach picks). A dirty tree is never touched: it warns once per new tip
-- and waits.
local pr = require('mpataki.review.pr')

local M = {}

-- A cascade moves several refs in quick succession; settle before checking.
M.debounce = 300

local state -- { root, branch, sha, reapply, warned }
local timer -- debounce timer for poke()

local function rev(root, ref)
  local r = pr.git(root, { 'rev-parse', '--verify', '--quiet', ref .. '^{commit}' })
  return r.code == 0 and vim.trim(r.stdout) or nil
end

function M.stop()
  state = nil
end

function M.following()
  return state and state.branch
end

-- One tick. Returns what happened, for probes:
-- 'idle' | 'stopped' | 'dirty' | 'elsewhere' | 'moved'.
function M.check()
  if not state then return 'idle' end
  local s = state
  local attached = pr.git(s.root, { 'symbolic-ref', '-q', 'HEAD' }).code == 0
  if attached or rev(s.root, 'HEAD') ~= s.sha then
    M.stop()
    return 'stopped'
  end
  local tip = rev(s.root, s.branch)
  if not tip or tip == s.sha then return 'idle' end
  if vim.trim(pr.git(s.root, { 'status', '--porcelain' }).stdout) ~= '' then
    if s.warned ~= tip then
      s.warned = tip
      vim.notify(('ladder: %s moved to %s; tree is dirty, not following'):format(s.branch, tip:sub(1, 8)),
        vim.log.levels.WARN)
    end
    return 'dirty'
  end
  -- reapply resolves the repo from the focused buffer (then cwd); with another
  -- repo's buffer focused it would pin that repo. Wait for focus to come back.
  if pr.current_root() ~= s.root then return 'elsewhere' end
  s.reapply() -- re-checks-out the branch tip, re-pins the base, calls start() again
  vim.notify(('ladder: following %s → %s'):format(s.branch, tip:sub(1, 8)))
  return 'moved'
end

function M.start(root, branch, reapply)
  local sha = rev(root, 'HEAD')
  if not sha then return M.stop() end
  state = { root = root, branch = branch, sha = sha, reapply = reapply }
end

-- Called by bin/ladder-notify over the nvim socket on every branch move in a
-- ladder repo. Returns at once (the hook never waits); a no-op unless
-- following. Debounced so a multi-rung cascade triggers one check.
function M.poke()
  if not state then return '' end
  timer = timer or vim.uv.new_timer()
  timer:stop()
  timer:start(M.debounce, 0, vim.schedule_wrap(M.check))
  return ''
end

vim.api.nvim_create_autocmd('FocusGained', { callback = function() M.check() end })

return M
