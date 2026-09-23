-- The PR commands must surface pr.info()'s real reason, not a generic one.
-- Regression for `local info, err = root and pr.info(root)`, where Lua's `and`
-- truncates the multi-return, so err was always nil and every failure read
-- "not in a git repo".
--
-- Asserted through nvim-notify's history: this config replaces vim.notify with
-- it, so the history IS what the user was shown (nothing reaches :messages).
package.path = vim.fn.expand('~/dotfiles/nvim/probes/review/?.lua') .. ';' .. package.path
local P = require('probe')

local function sh(argv, cwd)
  local r = vim.system(argv, { cwd = cwd, text = true }):wait()
  assert(r.code == 0, table.concat(argv, ' ') .. ' failed: ' .. (r.stderr or ''))
end

-- A real repo with a commit but no main/master and no PR: pr.info() fails with
-- 'could not find merge base', which is what the user needs to see.
local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
root = vim.uv.fs_realpath(root)
sh({ 'git', 'init', '-q', '-b', 'topic' }, root)
sh({ 'git', 'config', 'user.email', 'probe@example.com' }, root)
sh({ 'git', 'config', 'user.name', 'probe' }, root)
sh({ 'git', 'config', 'commit.gpgsign', 'false' }, root)
vim.fn.writefile({ 'hello' }, root .. '/file.txt')
sh({ 'git', 'add', 'file.txt' }, root)
sh({ 'git', '-c', 'commit.gpgsign=false', 'commit', '-q', '-m', 'only commit' }, root)

vim.cmd('edit ' .. vim.fn.fnameescape(root .. '/file.txt'))
P.wait(300)

local function notified()
  local lines = {}
  for _, e in ipairs(require('notify').history()) do
    table.insert(lines, table.concat(e.message, ' '))
  end
  return table.concat(lines, '\n')
end

pcall(vim.cmd, 'DiffviewPR')
P.wait(1000, function() return notified():find('DiffviewPR:', 1, true) ~= nil end)

local msgs = notified()
P.ok(msgs:find('DiffviewPR: could not find merge base', 1, true) ~= nil,
  "DiffviewPR reports pr.info's reason, not a generic 'not in a git repo'")
P.ok(msgs:find('DiffviewPR: not in a git repo', 1, true) == nil,
  'DiffviewPR does not mislabel a real repo as not-a-repo')

P.done()
