package.path = vim.fn.expand('~/dotfiles/nvim/probes/review/?.lua') .. ';' .. package.path
local P = require('probe')
local F = require('fixture')
local pr = require('mpataki.review.pr')

local fx = F.repo()
local file = fx.root .. '/sub/dir/file.txt'

P.eq(pr.root(file), fx.root, 'root from file path')
P.eq(pr.root(fx.root .. '/sub/dir'), fx.root, 'root from dir path')
P.eq(pr.relpath(fx.root, file), 'sub/dir/file.txt', 'relpath is repo-relative')
P.eq(pr.relpath(fx.root, '/definitely/elsewhere/z.txt'), nil, 'relpath nil outside root')

-- Scheme buffer names are not paths: root must return nil, not throw, or the
-- cwd fallback at every call site never runs.
P.eq(pr.root('diffview:///panels/1'), nil, 'root nil for a diffview panel name')
P.eq(pr.root('term://foo'), nil, 'root nil for a terminal buffer name')
P.ok(pr.common_dir(fx.root):match('/%.git$') ~= nil, 'common_dir ends in .git')

-- cwd must not matter: chdir into the subdir and resolve again
vim.fn.chdir(fx.root .. '/sub/dir')
P.eq(pr.relpath(pr.root(file), file), 'sub/dir/file.txt', 'relpath independent of cwd')

-- current_root reads the buffer first: cwd here is a non-repo directory.
local outside = vim.fn.tempname()
vim.fn.mkdir(outside, 'p')
vim.fn.chdir(outside)
vim.cmd('edit ' .. vim.fn.fnameescape(file))
P.eq(pr.current_root(), fx.root, 'current_root resolves from the buffer, not cwd')

local info, err = pr.info(fx.root)
P.ok(info ~= nil, 'info resolves without a PR: ' .. tostring(err))
P.eq(info and info.base_sha, fx.base_sha, 'base_sha falls back to merge-base with main')
P.eq(info and info.number, nil, 'no PR number without gh PR')
-- The fixture has no remote, so `gh pr view` fails here. Its reason has to
-- survive: "no PR for this branch" is a different problem with a different fix
-- than unauthenticated / offline / rate-limited, which all land in the same
-- place. (The gh *api* surface is faked in every probe; this is `gh pr view`
-- failing locally against a remote-less repo, no network involved.)
P.ok(type(info and info.pr_err) == 'string' and info.pr_err ~= '',
  'gh pr view failure is recorded as pr_err: ' .. tostring(info and info.pr_err))
P.ok(info and info.pr_err and not info.pr_err:find('\n', 1, true), 'pr_err is a single line')

-- A hung git (a credential prompt, an unreachable host) must not freeze the
-- editor: every call is bounded, and the kill explains itself rather than
-- failing with an empty stderr.
P.eq(pr.timeouts.git, 10000, 'git calls wait 10s')
P.eq(pr.timeouts.gh, 15000, 'gh pr view waits 15s')
local real_git_timeout = pr.timeouts.git
pr.timeouts.git = 150
local slow = pr.git(fx.root, { '-c', 'alias.slow=!sleep 5', 'slow' })
pr.timeouts.git = real_git_timeout
P.ok(slow.code ~= 0, 'a git call past the timeout fails rather than hanging')
P.ok(slow.stderr:find('timed out after 0.15s', 1, true) ~= nil,
  'the timeout names itself: ' .. tostring(slow.stderr))

local bad, bad_err = pr.info(nil)
P.eq(bad, nil, 'info(nil) refuses to fall back to nvim cwd')
P.eq(type(bad_err), 'string', 'info(nil) explains itself')

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

-- a hunk header inside diff *content* is body text, not a hunk
local body = pr.parse_hunk_ranges(table.concat({
  'diff --git a/x b/x',
  '@@ -1,1 +1,2 @@',
  ' ctx',
  '+@@ -1,2 +3,4 @@',
}, '\n'))
P.eq(#body, 1, 'hunk header in content is not a hunk')
P.eq(body[1] and body[1].s, 1, 'body hunk start')
P.eq(body[1] and body[1].e, 2, 'body hunk end')

-- Forced color must not break hunk parsing: a colored `@@` header no longer
-- matches '^@@'. color.ui=always is the user-config twin of the CLICOLOR_FORCE
-- the runner neutralizes, and both land on the same `git diff`.
pr.git(fx.root, { 'config', 'color.ui', 'always' })

local live = pr.diff_ranges(fx.root, fx.base_sha, fx.head_sha, 'sub/dir/file.txt')
P.ok(live ~= nil and #live > 0, 'diff_ranges parses hunks under color.ui=always')
P.ok(pr.in_ranges(live, 5), 'changed line 5 in diff')
P.ok(pr.in_ranges(live, 2), 'context line 2 in diff (U3)')
P.ok(pr.in_ranges(live, 11), 'appended line 11 in diff')
P.ok(not pr.in_ranges(live, 1), 'line 1 outside diff')

-- An unfetched head: the diff itself fails, and that must not read as "no
-- hunks" (callers would then refuse every line as outside the diff).
local none, none_err = pr.diff_ranges(fx.root, fx.base_sha, ('0'):rep(40), 'sub/dir/file.txt')
P.eq(none, nil, 'diff_ranges returns nil when git diff fails')
P.ok(type(none_err) == 'string' and none_err ~= '', 'diff_ranges returns the git error: ' .. tostring(none_err))
P.ok(not none_err:find('\n', 1, true), 'error is a single line')

P.done()
