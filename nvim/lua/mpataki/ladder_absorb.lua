-- <leader>cl: hand this review worktree's uncommitted edits to the agent. The
-- same float as <leader>cc takes optional context; `:w` sends the Claude pane
-- a message naming the worktree, the branch being viewed and the changed files,
-- pointing it at pr-ladder's "Review-worktree edits". An empty body still
-- sends: the edits are the request. The agent commits them in the ladder and
-- cascades; bin/ladder-notify then re-points this worktree at the new tip once
-- its content matches, so it comes back clean and following resumes.
local ask = require('mpataki.ask')
local capture = require('mpataki.review.capture')
local follow = require('mpataki.ladder_follow')
local payload = require('mpataki.ask.payload')
local pr = require('mpataki.review.pr')
local target = require('mpataki.ask.target')
local tmux = require('mpataki.ask.tmux')

local M = {}

local function notify_err(msg)
  vim.notify('absorb: ' .. msg, vim.log.levels.ERROR)
end

-- view: { branch, base? } (base = the rung below, when viewing a rung).
function M.message(root, view, files, context)
  local where = view.base and ('%s (rung below: %s)'):format(view.branch, view.base) or view.branch
  local lines = {
    ('Review-worktree edits: I changed files in %s while viewing %s. '
      .. 'Absorb them per the pr-ladder skill\'s "Review-worktree edits" section: '
      .. 'commit them in the ladder, cascade, and leave my worktree alone.'):format(root, where),
    'Changed: ' .. table.concat(files, ', '),
  }
  if context ~= '' then
    table.insert(lines, '')
    table.insert(lines, context)
  end
  return table.concat(lines, '\n')
end

-- Repo-relative paths with uncommitted changes, untracked included.
function M.changed(root)
  local r = pr.git(root, { 'status', '--porcelain', '--untracked-files=all' })
  if r.code ~= 0 then return nil end
  local files = {}
  for line in r.stdout:gmatch('[^\n]+') do
    table.insert(files, (line:sub(4):gsub('^.* %-> ', '')))
  end
  return files
end

function M.absorb()
  local root = pr.current_root()
  if not root then return notify_err('not in a git repo') end
  local files = M.changed(root)
  if not files then return notify_err('git status failed') end
  if #files == 0 then return vim.notify('absorb: no uncommitted edits') end
  local view = follow.read(root)
  if not view then
    local branch = pr.branch(root)
    view = { branch = branch or ('detached ' .. vim.trim(pr.git(root, { 'rev-parse', '--short', 'HEAD' }).stdout)) }
  end
  ask.resolve(function(row)
    capture.open({
      title = ('absorb %d edit(s) on %s → claude %s'):format(#files, view.branch, target.label(row)),
      on_save = function(text)
        local ok, err = tmux.send(row.id, M.message(root, view, files, payload.body(text)))
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
  vim.keymap.set('n', '<leader>cl', M.absorb, { desc = 'Hand review-worktree edits to Claude (ladder)' })
end

return M
