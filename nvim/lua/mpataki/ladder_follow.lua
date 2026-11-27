-- Keeps a <leader>gp ladder view on its branch's latest head. git does the
-- moving; nvim only reacts to its own disk.
--
-- State lives in this worktree's git dir, <gitdir>/ladder-follow:
--   line 1: the branch being followed
--   line 2: the ref the diff base is pinned to (the rung below), or empty
-- bin/ladder-notify (global reference-transaction hook, git/gitconfig) reads it
-- and, when that branch moves, checks out the new tip here — if HEAD is
-- detached on the old tip and the tree is clean. Works with nvim closed.
--
-- The review worktree stays detached on purpose: git refuses to rebase or move
-- a branch checked out in another worktree, and cascades must always move
-- rungs. Buffers reload via the checktime autocmds (mpataki.autocmd); this
-- module watches HEAD and re-resolves the pinned base (pr.lua: merge-base with
-- the rung below, which a cascade shifts) for the overlay and tree.
local pr = require('mpataki.review.pr')

local M = {}

M.debounce = 200

local watchers = {} -- root -> { fs = fs_event, timer = timer }

local function state_file(root)
  local r = pr.git(root, { 'rev-parse', '--absolute-git-dir' })
  if r.code ~= 0 then return nil end
  return vim.trim(r.stdout) .. '/ladder-follow'
end

-- { branch, base } for root's worktree, or nil when not following.
function M.read(root)
  local f = state_file(root)
  if not f or vim.fn.filereadable(f) == 0 then return nil end
  local lines = vim.fn.readfile(f)
  if not lines[1] or lines[1] == '' then return nil end
  return { branch = lines[1], base = (lines[2] ~= '' and lines[2]) or nil }
end

function M.following(root)
  local s = M.read(root)
  return s and s.branch
end

-- HEAD moved (followed, or anything else): pinned views re-resolve their base.
local function refresh(root)
  if pr.current_root() ~= root or not pr.pinned(root) then return end
  vim.cmd('silent! checktime')
  vim.cmd('silent DiffPRBase')
  local info = pr.info(root)
  if not info then return end
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'neo-tree' then
      vim.cmd('Neotree git_base=' .. info.base_sha)
      break
    end
  end
end

-- Watch the git dir, not the HEAD file: git replaces HEAD by rename, which a
-- file watch loses track of on macOS.
local function watch(root)
  if watchers[root] then return end
  local f = state_file(root)
  if not f then return end
  local fs, timer = vim.uv.new_fs_event(), vim.uv.new_timer()
  fs:start(vim.fs.dirname(f), {}, function(err, name)
    if err or name ~= 'HEAD' then return end
    timer:stop()
    timer:start(M.debounce, 0, vim.schedule_wrap(function() refresh(root) end))
  end)
  watchers[root] = { fs = fs, timer = timer }
end

-- Follow `branch`; pin the diff base to merge-base(HEAD, base_ref) when given.
function M.start(root, branch, base_ref)
  local f = state_file(root)
  if not f then return end
  vim.fn.writefile({ branch, base_ref or '' }, f)
  pr.pin_base(root, base_ref)
  watch(root)
end

function M.stop(root)
  local f = state_file(root)
  if f then vim.fn.delete(f) end
  pr.pin_base(root, nil)
end

-- A worktree left following across an nvim restart picks its pin back up.
function M.restore(root)
  local s = root and M.read(root)
  if not s then return end
  pr.pin_base(root, s.base)
  watch(root)
end

vim.api.nvim_create_autocmd('VimEnter', {
  callback = function() M.restore(pr.current_root()) end,
})

return M
