package.path = vim.fn.expand('~/dotfiles/nvim/probes/review/?.lua') .. ';' .. package.path
local P = require('probe')
local F = require('fixture')
local pr = require('mpataki.review.pr')
local store = require('mpataki.review.store')
local render = require('mpataki.review.render')
local review = require('mpataki.review')

-- One virt_lines mark per rendered comment; the range tints sharing the
-- namespace would otherwise inflate a count of "how many comments are drawn".
local function comment_marks(buf)
  local n = 0
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, render.ns, 0, -1, { details = true })) do
    if m[4].virt_lines then n = n + 1 end
  end
  return n
end

-- startinsert/stopinsert echo '-- (insert) --' into headless output otherwise.
vim.o.showmode = false

-- vim.notify is nvim-notify here: assert through its history, never override it.
local function notified()
  local lines = {}
  for _, e in ipairs(require('notify').history()) do
    table.insert(lines, table.concat(e.message, ' '))
  end
  return table.concat(lines, '\n')
end

-- Count gh invocations: the passive BufWinEnter path must never be the first
-- thing to shell out to gh (it blocks the editor on the network).
local gh_calls, spawns = 0, 0
local real_system = vim.system
vim.system = function(argv, ...)
  spawns = spawns + 1
  if argv[1] == 'gh' then gh_calls = gh_calls + 1 end
  return real_system(argv, ...)
end

-- Pretend the fixture repo is PR #7 by seeding pr's cache: no gh in probes.
local fx = F.repo()
pr.clear_cache()
local info = pr.info(fx.root)
info.number = 7
info.head = fx.head_sha
info.url = 'https://example.invalid/pr/7'
gh_calls = 0

vim.cmd('edit ' .. vim.fn.fnameescape(fx.root .. '/sub/dir/file.txt'))
P.wait(100)
P.eq(gh_calls, 0, 'BufWinEnter does not shell to gh (cache seeded, no review files)')
local code_buf = vim.api.nvim_get_current_buf()
local code_win = vim.api.nvim_get_current_win()
local ctx, err = review.context(code_buf)
P.ok(ctx ~= nil, 'context resolves: ' .. tostring(err))
P.eq(ctx and ctx.relpath, 'sub/dir/file.txt', 'context relpath')
P.eq(ctx and ctx.file, store.path(info.common_dir, 7), 'context store file')

-- A second repo with no review files: opening a file there must not run gh.
local other = F.repo()
vim.cmd('edit ' .. vim.fn.fnameescape(other.root .. '/sub/dir/file.txt'))
P.wait(100)
P.eq(gh_calls, 0, 'BufWinEnter in a repo without review files never runs gh')

-- gh failing is not the same as this branch having no PR: the fixture has no
-- remote, so `gh pr view` fails, and the reason has to reach the user instead
-- of "gh pr view found none" (which would send them to open a PR they have).
local other_info = pr.info(other.root)
P.ok(type(other_info and other_info.pr_err) == 'string' and other_info.pr_err ~= '',
  'pr.info records why gh pr view failed: ' .. tostring(other_info and other_info.pr_err))
local nopr_ctx, nopr_err = review.context()
P.eq(nopr_ctx, nil, 'no context without a PR')
P.ok(nopr_err and nopr_err:find('no PR for this branch: ' .. tostring(other_info.pr_err), 1, true) ~= nil,
  'the context error carries the gh failure: ' .. tostring(nopr_err))
gh_calls = 0

vim.api.nvim_set_current_buf(code_buf)

-- A repo with no main/master: pr.info fails, and the failure is cached so the
-- passive path does not re-run gh + two merge-base attempts per window entry.
local bare = vim.fn.tempname()
vim.fn.mkdir(bare, 'p')
bare = vim.uv.fs_realpath(bare)
local function sh(argv)
  assert(real_system(argv, { cwd = bare, text = true }):wait().code == 0, table.concat(argv, ' '))
end
sh({ 'git', 'init', '-q', '-b', 'topic' })
sh({ 'git', '-c', 'user.email=p@x', '-c', 'user.name=p', '-c', 'commit.gpgsign=false', 'commit', '-q', '--allow-empty', '-m', 'only' })
local _, err1 = pr.info(bare)
P.ok(err1 ~= nil, 'pr.info fails without a merge base')
spawns = 0
local _, err2 = pr.info(bare)
P.eq(spawns, 0, 'second pr.info on a failing root spawns no process (failure cached)')
P.eq(err2, err1, 'cached failure returns the same error')
pr.info(bare, { refresh = true })
P.ok(spawns > 0, 'refresh bypasses the cached failure')

-- Line 1 is outside the diff: refuse. nvim-notify records history on the
-- next tick, so wait for it.
vim.api.nvim_win_set_cursor(code_win, { 1, 0 })
review.comment()
P.eq(vim.api.nvim_get_current_win(), code_win, 'no float outside diff')
P.wait(500, function() return notified():find('not in the PR diff', 1, true) ~= nil end)
P.ok(notified():find('not in the PR diff', 1, true) ~= nil, 'refusal message')

-- A PR head that is not fetched locally: git diff fails, and the message must
-- blame the missing ref, not the line.
info.head = ('0'):rep(40)
vim.api.nvim_win_set_cursor(code_win, { 5, 0 })
review.comment()
P.eq(vim.api.nvim_get_current_win(), code_win, 'no float when the diff itself fails')
P.wait(500, function() return notified():find('no diff for sub/dir/file.txt', 1, true) ~= nil end)
P.ok(notified():find('no diff for sub/dir/file.txt against PR head 00000000', 1, true) ~= nil,
  'failed diff names the file and head, not the line')
info.head = fx.head_sha

-- Line 5 is changed: float opens, write body, :w saves. nvim resolves
-- relative='cursor' into relative='win' + the cursor's row at open time, so
-- assert the resolved shape: below the cursor line, in the code window.
vim.api.nvim_win_set_cursor(code_win, { 5, 0 })
local cursor_row = vim.fn.winline() - 1
local code_spell = vim.wo[code_win].spell
review.comment()
local float_win = vim.api.nvim_get_current_win()
P.ok(float_win ~= code_win, 'float opened')
local cfg = vim.api.nvim_win_get_config(float_win)
P.eq(cfg.win, code_win, 'anchored in the code window')
P.eq(cfg.anchor, 'NW', 'opens below the cursor when there is room')
P.eq(cfg.row, cursor_row + 1, 'anchored one row under the cursor line')
P.eq(vim.bo.filetype, 'markdown', 'float is markdown')
-- ftplugin/markdown.lua sets window-local 'spell'. Set the filetype before the
-- window exists and that setting goes to a throwaway autocmd window, leaving
-- the prose float unchecked.
P.ok(vim.wo[float_win].spell, 'float has spell on')
P.eq(vim.wo[code_win].spell, code_spell, "opening the float left the code window's spell alone")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'looks wrong', '', 'see above' })
local ok_write, write_err = pcall(vim.cmd, 'write')
P.ok(ok_write, ':write in the float raises no error: ' .. tostring(write_err))
P.eq(#store.read(ctx.file).entries, 1, 'entry is on disk when :write returns (save is not deferred)')
P.wait(200)
P.eq(vim.api.nvim_get_current_win(), code_win, 'float closed after :w')
P.ok(not vim.api.nvim_win_is_valid(float_win), 'float window is gone after :w')

local doc = store.read(ctx.file)
P.eq(#doc.entries, 1, 'entry saved')
P.eq(doc.entries[1].line, 5, 'anchored line 5')
P.eq(doc.entries[1].body, 'looks wrong\n\nsee above', 'body saved')
P.eq(doc.header.repo, nil, 'header repo unset until push sets it')
P.eq(comment_marks(code_buf), 1, 'rendered after save')

-- Reopen on the same line: body preloaded; q cancels without change.
review.comment()
P.eq(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n'), 'looks wrong\n\nsee above', 'existing body preloaded')
vim.cmd('stopinsert') -- cancel the pending startinsert so 'q' is a normal-mode key
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>q', true, false, true), 'x', false)
P.wait(200)
P.eq(vim.api.nvim_get_current_win(), code_win, 'q closes float')
P.eq(store.read(ctx.file).entries[1].body, 'looks wrong\n\nsee above', 'q left entry unchanged')

-- :q on a modified float closes it too (no E37 on a scratch buffer) and saves nothing.
review.comment()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'abandoned edit' })
local ok_q, q_err = pcall(vim.cmd, 'quit')
P.ok(ok_q, ':q closes a modified float without E37: ' .. tostring(q_err))
P.wait(100)
P.eq(vim.api.nvim_get_current_win(), code_win, ':q returns to the code window')
P.eq(store.read(ctx.file).entries[1].body, 'looks wrong\n\nsee above', ':q left entry unchanged')
P.eq(vim.fn.bufexists('review://sub/dir/file.txt:5'), 0, 'cancelled float buffer is wiped, not left hidden')

-- :wq saves and closes the float only. (A close from inside BufWriteCmd lets
-- the quit half of :wq take the code window instead.)
vim.api.nvim_win_set_cursor(code_win, { 7, 0 })
review.comment()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'via wq' })
local ok_wq, wq_err = pcall(vim.cmd, 'wq')
P.ok(ok_wq, ':wq in the float raises no error: ' .. tostring(wq_err))
P.wait(200)
P.ok(vim.api.nvim_win_is_valid(code_win), ':wq leaves the code window open')
P.eq(vim.api.nvim_get_current_win(), code_win, ':wq returns to the code window')
P.ok(store.find(store.read(ctx.file), 'sub/dir/file.txt', 7) ~= nil, ':wq saved the entry')

-- A float left open (focus moved away) is refocused, not duplicated (E95 on the name).
review.comment()
local first_float = vim.api.nvim_get_current_win()
vim.api.nvim_set_current_win(code_win)
review.comment()
P.eq(vim.api.nvim_get_current_win(), first_float, 'second comment() on the same anchor refocuses the open float')
vim.cmd('stopinsert')
vim.api.nvim_feedkeys('q', 'x', false)
P.wait(100)
P.eq(vim.api.nvim_get_current_win(), code_win, 'refocused float still closes on q')

-- Visual range 9..11 → range entry, through the real x-mode keymap: ':' from
-- visual mode is what supplies the '<,'> range. (`:normal! V2j` leaves visual
-- mode active with the marks unset, so a scripted "'<,'>ReviewComment" is E20.)
vim.api.nvim_win_set_cursor(code_win, { 9, 0 })
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('V2j<leader>gc', true, false, true), 'x', false)
P.wait(100)
P.eq(vim.api.nvim_buf_get_name(0), 'review://sub/dir/file.txt:9-11', 'x-mode <leader>gc opens a 9-11 range float')
local range_win = vim.api.nvim_get_current_win()

-- With the 9-11 float still open, a single-line comment on 9 is a different
-- anchor: it must get its own float, not refocus (or wipe) the range draft via
-- bufnr()'s partial name match.
vim.api.nvim_set_current_win(code_win)
vim.api.nvim_win_set_cursor(code_win, { 9, 0 })
review.comment()
P.eq(vim.api.nvim_buf_get_name(0), 'review://sub/dir/file.txt:9', 'single-line anchor opens its own float beside the range float')
P.ok(vim.api.nvim_get_current_win() ~= range_win, 'it is a separate window')
vim.cmd('stopinsert')
vim.api.nvim_feedkeys('q', 'x', false)
P.wait(100)
P.ok(vim.api.nvim_win_is_valid(range_win), 'range float survived')
vim.api.nvim_set_current_win(range_win)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'range note' })
vim.cmd('write')
P.wait(200)
local r = store.find(store.read(ctx.file), 'sub/dir/file.txt', 11, 9)
P.ok(r ~= nil, 'range entry saved as 9-11')

-- …and it reopens from *inside* the range: normal-mode <leader>gc on line 10
-- used to key on the cursor line alone, so editing a range comment meant
-- re-selecting the identical range or accreting a second comment on line 10.
vim.api.nvim_win_set_cursor(code_win, { 10, 0 })
review.comment()
P.eq(vim.api.nvim_buf_get_name(0), 'review://sub/dir/file.txt:9-11',
  'cursor inside a range reopens the range float')
local rtitle = vim.api.nvim_win_get_config(0).title
P.ok(vim.inspect(rtitle):find('sub/dir/file.txt:9-11', 1, true) ~= nil,
  'the float title names the range: ' .. vim.inspect(rtitle))
P.eq(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n'), 'range note',
  '…with the existing range body in it')
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'range note, edited' })
vim.cmd('write')
P.wait(200)
local redited = store.read(ctx.file)
P.eq(store.find(redited, 'sub/dir/file.txt', 11, 9).body, 'range note, edited',
  'saving from inside the range updates the 9-11 entry')
P.eq(store.find(redited, 'sub/dir/file.txt', 10), nil,
  'and creates no single-line entry on the cursor line')

-- Empty body deletes.
vim.api.nvim_win_set_cursor(code_win, { 5, 0 })
review.comment()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { '' })
vim.cmd('write')
P.wait(200)
P.eq(store.find(store.read(ctx.file), 'sub/dir/file.txt', 5), nil, 'empty body deleted entry')

-- <C-s> from insert mode saves and leaves insert mode, so the user does not
-- land in insert mode in the code buffer.
vim.api.nvim_win_set_cursor(code_win, { 6, 0 })
review.comment()
vim.cmd('stopinsert')
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('ihello<C-s>', true, false, true), 'x!', false)
P.wait(200)
P.eq(vim.api.nvim_get_mode().mode, 'n', '<C-s> from insert ends in normal mode')
P.eq(vim.api.nvim_get_current_win(), code_win, '<C-s> closed the float')
P.ok(store.find(store.read(ctx.file), 'sub/dir/file.txt', 6) ~= nil, '<C-s> saved the entry')

-- Near the bottom of the screen the float opens above the cursor line instead
-- of being slid back up over it.
vim.o.lines = 12
vim.api.nvim_win_set_cursor(code_win, { 8, 0 })
review.comment()
P.eq(vim.api.nvim_win_get_config(0).anchor, 'SW', 'opens above the cursor when there is no room below')
vim.cmd('stopinsert')
vim.api.nvim_feedkeys('q', 'x', false)
P.wait(100)
vim.o.lines = 24

-- Quickfix works from a buffer with no file (cwd resolves the repo).
vim.fn.chdir(fx.root)
vim.cmd('enew')
review.quickfix()
P.eq(#vim.fn.getqflist(), 3, 'quickfix lists remaining entries from a no-file buffer')
vim.cmd('cclose')
vim.api.nvim_set_current_buf(code_buf)

-- BufWinEnter renders once a review file exists.
render.clear(code_buf)
vim.cmd('doautocmd BufWinEnter')
P.eq(comment_marks(code_buf), 3, 'BufWinEnter renders pending entries')

-- A write that cannot land must keep the float open with the draft in it: the
-- old silent store.write closed the float and reported nothing, losing the
-- comment. Read-only file, so mkdir succeeds and writefile is what refuses.
vim.fn.setfperm(ctx.file, 'r--r--r--')
vim.api.nvim_win_set_cursor(code_win, { 4, 0 })
review.comment()
local ro_float = vim.api.nvim_get_current_win()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'this cannot land' })
pcall(vim.cmd, 'write')
P.wait(500, function() return notified():find('cannot write', 1, true) ~= nil end)
P.ok(notified():find('cannot write', 1, true) ~= nil, 'a failed write is reported')
P.eq(vim.api.nvim_get_current_win(), ro_float, 'the float stays open when the write fails')
P.ok(vim.bo.modified, '…with the draft still in it, unsaved')
vim.fn.setfperm(ctx.file, 'rw-r--r--')
vim.cmd('stopinsert')
vim.api.nvim_feedkeys('q', 'x', false)
P.wait(100)
P.eq(vim.api.nvim_get_current_win(), code_win, 'cancelling the failed float returns to the code window')
P.eq(store.find(store.read(ctx.file), 'sub/dir/file.txt', 4), nil, 'nothing was written')

-- BufWinEnter fires on every window entry, for every file, forever. Measured
-- at 3 git spawns per entry before this: pr.root, pr.common_dir, then
-- M.context resolving pr.root all over again. common_dir is memoized per root
-- and context is handed the root, leaving the root lookup itself. (Root is not
-- memoized by directory: a path can stop being in a repo, and the lookup is
-- the cheapest of the three.)
vim.fn.writefile({ 'second file' }, fx.root .. '/sub/dir/second.txt')
vim.cmd('edit ' .. vim.fn.fnameescape(fx.root .. '/sub/dir/second.txt'))
P.wait(200)
spawns, gh_calls = 0, 0
vim.cmd('doautocmd BufWinEnter')
P.ok(spawns <= 1, 'BufWinEnter in a reviewed repo spawns at most one process, got ' .. tostring(spawns))
P.eq(gh_calls, 0, '…and never gh')
vim.api.nvim_set_current_buf(code_buf)

P.ok(vim.fn.maparg('<leader>gc', 'n') ~= '', '<leader>gc mapped (n)')
P.ok(vim.fn.maparg('<leader>gc', 'x') ~= '', '<leader>gc mapped (v)')
P.ok(vim.fn.maparg('<leader>gC', 'n') ~= '', '<leader>gC mapped (n)')
P.ok(vim.fn.exists(':ReviewPush') == 2, ':ReviewPush exists')
P.ok(vim.fn.exists(':ReviewPull') == 2, ':ReviewPull exists')
P.ok(vim.fn.exists(':ReviewRefresh') == 2, ':ReviewRefresh exists')

vim.system = real_system

-- :wqa from a modified float: write-all, then quit-all with no event-loop tick
-- between them. The entry must already be on disk when nvim leaves.
vim.api.nvim_win_set_cursor(code_win, { 8, 0 })
review.comment()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'via wqa' })
vim.api.nvim_create_autocmd('VimLeavePre', {
  callback = function()
    P.ok(store.find(store.read(ctx.file), 'sub/dir/file.txt', 8) ~= nil, ':wqa saved the entry before nvim left')
    P.done()
  end,
})
vim.cmd('wqa')
