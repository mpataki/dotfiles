-- Scenario: dao/model boundary. The pod list comes back empty; the question
-- is where the model layer asks the dao layer for rows, and whether Pod.List
-- is even the implementation that runs.
--
--  1. open dao/pod.go:80 on Pod.List; :SpelunkStart daomodel.
--  2. gi on List — what interface is this satisfying?
--  3. pick Lister.List (dao/types.go:69).
--  4. note it: the dao contract.
--  5. gi on Lister.List — who else implements it? (Pod.List, the root, is
--     one of them: the answer loops back.)
--  6. pick Generic.List — the fallback for resources without a typed dao.
--  7. note it.
--  8. incoming calls on Generic.List — who calls a concrete lister directly?
--  9. pick one caller and look at it.
-- 10. <C-o> back to Generic.List.
-- 11. jump back up to Lister.List: who calls through the interface?
-- 12. gr on Lister.List.
-- 13. pick a caller in internal/model — the boundary.
-- 14. note it.
-- Left unexplored on purpose: most implementations and most references.
local D = dofile(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h') .. '/drive.lua')
local POD, TYPES, GEN = 'internal/dao/pod.go', 'internal/dao/types.go', 'internal/dao/generic.go'

D.begin('daomodel')

-- 1. the concrete lister
D.go(POD, 80, '%) ()List%(')
D.ready()
vim.cmd('SpelunkStart daomodel')
D.step(':SpelunkStart on Pod.List')

-- 2. which interface?
local q = D.ask(vim.lsp.buf.implementation)
D.step('gi on Pod.List (interfaces it satisfies)')

-- 3. Lister.List (a single answer jumps straight there)
if q then
  D.pick(q, function(_, file) return file == TYPES end, 'Lister.List')
end
D.step('at Lister.List')

-- 4. note
D.note('the dao contract every resource implements')
D.step('note on Lister.List')

-- 5. who else implements it?
D.aim(69, '^%s*()List%(')
q = D.ask(vim.lsp.buf.implementation)
D.step('gi on Lister.List (implementations)')

-- 6. the generic fallback
D.pick(q, function(_, file) return file == GEN end, 'Generic.List')
D.step('jump to Generic.List')

-- 7. note
D.note('fallback for resources without a typed dao')
D.step('note on Generic.List')

-- 8. who calls a concrete lister directly?
D.aim(vim.fn.line('.'), '%) ()List%(')
q = D.ask(vim.lsp.buf.incoming_calls)
D.step('incoming calls on Generic.List')

-- 9. look at one caller
D.pick(q, function(_, file) return file:find('^internal/model/') ~= nil end, 'model caller of Generic.List')
D.step('jump to a caller of Generic.List')

-- 10. back
D.back()
D.step('<C-o> back to Generic.List')

-- 11. up to the interface
D.go(TYPES, 69, '^%s*()List%(')
D.step('jump back up to Lister.List')

-- 12. who calls through the interface?
q = D.ask(function() vim.lsp.buf.references({ includeDeclaration = false }) end)
D.step('gr on Lister.List')

-- 13. the model side of the boundary
D.pick(q, function(_, file) return file:find('^internal/model/') ~= nil end, 'model caller of Lister.List')
D.step('jump to a model-side caller')

-- 14. note
D.note('model asks dao for rows here')
D.step('note on the model-side caller')

D.finish()
