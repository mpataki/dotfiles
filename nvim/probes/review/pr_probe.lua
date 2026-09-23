package.path = vim.fn.expand('~/dotfiles/nvim/probes/review/?.lua') .. ';' .. package.path
local P = require('probe')
local F = require('fixture')
local pr = require('mpataki.review.pr')

local fx = F.repo()
local file = fx.root .. '/sub/dir/file.txt'

P.eq(pr.root(file), fx.root, 'root from file path')
P.eq(pr.root(fx.root .. '/sub/dir'), fx.root, 'root from dir path')
P.eq(pr.relpath(fx.root, file), 'sub/dir/file.txt', 'relpath is repo-relative')
P.ok(pr.common_dir(fx.root):match('/%.git$') ~= nil, 'common_dir ends in .git')

-- cwd must not matter: chdir into the subdir and resolve again
vim.fn.chdir(fx.root .. '/sub/dir')
P.eq(pr.relpath(pr.root(file), file), 'sub/dir/file.txt', 'relpath independent of cwd')

local info, err = pr.info(fx.root)
P.ok(info ~= nil, 'info resolves without a PR: ' .. tostring(err))
P.eq(info and info.base_sha, fx.base_sha, 'base_sha falls back to merge-base with main')
P.eq(info and info.number, nil, 'no PR number without gh PR')

local ranges = pr.parse_hunk_ranges(table.concat({
  'diff --git a/x b/x',
  '@@ -2,7 +2,8 @@',
  ' ctx',
  '@@ -20 +21,2 @@',
  '+a',
}, '\n'))
P.eq(#ranges, 2, 'two hunks parsed')
P.eq(ranges[1].s, 2, 'hunk1 start'); P.eq(ranges[1].e, 9, 'hunk1 end')
P.eq(ranges[2].s, 21, 'hunk2 start'); P.eq(ranges[2].e, 22, 'hunk2 end (count 2)')

local live = pr.diff_ranges(fx.root, fx.base_sha, fx.head_sha, 'sub/dir/file.txt')
P.ok(pr.in_ranges(live, 5), 'changed line 5 in diff')
P.ok(pr.in_ranges(live, 2), 'context line 2 in diff (U3)')
P.ok(pr.in_ranges(live, 11), 'appended line 11 in diff')
P.ok(not pr.in_ranges(live, 1), 'line 1 outside diff')

P.done()
