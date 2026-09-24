-- Scenario: command dispatch. A user types `:pods` and gets the wrong view.
-- Start at Command.run, the dispatcher, and work out both directions: how a
-- keystroke gets here, and how run turns a command into a concrete view.
--
--  1. open view/command.go:141 on run; :SpelunkStart command-dispatch.
--  2. incoming calls on run — who dispatches commands?
--  3. gotoResource (app.go:694) is the App-level entry: pick it.
--  4. incoming calls on gotoResource — where does the keystroke come from?
--  5. pick App.gotoCmd (app.go:630; five other views have a gotoCmd too):
--     the `:` prompt's Enter handler.
--  6. note it: the prompt ends here.
--  7. that's the "how did I get here"; jump back to run to go down instead.
--  8. outgoing calls from run — what does it do with the command?
--  9. exec is where the component is shown: pick its call site, gd into
--     command.go:298.
-- 10. outgoing calls from exec — its recover() path calls run again: the
--     code loops, which should draw as a back-edge.
-- 11. follow comp: gd on c.app.inject(comp, ...) into App.inject.
-- 12. inject calls c.Init on the component — gi there: which concrete views
--     can this be?
-- 13. pick Browser.Init — the generic resource view `:pods` ends up in.
-- 14. note it.
-- 15. back up to run by jumping to it (retreat to an ancestor).
-- Left unexplored on purpose: the other callers of run, most callees, and all
-- but one of the Init implementations.
local D = dofile(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h') .. '/drive.lua')
local CMD, APP = 'internal/view/command.go', 'internal/view/app.go'

D.begin('dispatch')

-- 1. the dispatcher
D.go(CMD, 141, '%) ()run%(')
D.ready()
vim.cmd('SpelunkStart dispatch')
D.step(':SpelunkStart on Command.run')

-- 2. who dispatches?
local q = D.ask(vim.lsp.buf.incoming_calls)
D.step('incoming calls on run')

-- 3. the App-level entry
D.pick(q, function(it) return it.text == 'gotoResource' end, 'gotoResource')
D.step('jump to gotoResource')

-- 4. where does the keystroke come from?
D.aim(693, '%) ()gotoResource%(')
q = D.ask(vim.lsp.buf.incoming_calls)
D.step('incoming calls on gotoResource')

-- 5. the prompt handler
D.pick(q, function(it, file) return it.text == 'gotoCmd' and file == APP end, 'App.gotoCmd')
D.step('jump to gotoCmd')

-- 6. note
D.note('the : prompt Enter handler; dispatch starts here')
D.step('note on gotoCmd')

-- 7. back to run to go down
D.go(CMD, 141, '%) ()run%(')
D.step('jump back to run')

-- 8. what does run do?
q = D.ask(vim.lsp.buf.outgoing_calls)
D.step('outgoing calls from run')

-- 9. exec shows the component
D.pick(q, function(it) return it.text == 'exec' end, 'exec call site')
D.ask(vim.lsp.buf.definition)
D.step('gd into exec')

-- 10. exec's outgoing calls include run (recover path)
D.aim(298, '%) ()exec%(')
q = D.ask(vim.lsp.buf.outgoing_calls)
D.step('outgoing calls from exec (run is among them)')

-- 11. follow comp into inject
D.aim(322, 'app%.()inject%(')
D.ask(vim.lsp.buf.definition)
D.step('gd into App.inject')

-- 12. which concrete views can comp be?
D.aim(702, 'c%.()Init%(')
q = D.ask(vim.lsp.buf.implementation)
D.step('gi on c.Init in inject')

-- 13. the generic browser
D.pick(q, function(_, file) return file == 'internal/view/browser.go' end, 'Browser.Init')
D.step('jump to Browser.Init')

-- 14. note
D.note(':pods lands in the generic Browser')
D.step('note on Browser.Init')

-- 15. back up to run
D.go(CMD, 141, '%) ()run%(')
D.step('jump back up to run')

D.finish()
