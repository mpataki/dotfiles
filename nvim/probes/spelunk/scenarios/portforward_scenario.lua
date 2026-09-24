-- Scenario: port-forward indicator. A bug report says the PF column shows no
-- marker for a pod that is being forwarded. No :SpelunkStart: the first call
-- hierarchy request auto-starts the session (the "just navigate" path).
--
--  1. open view/pod.go:66 on portForwardIndicator — the function that paints
--     the PF column; this is where the error "lives".
--  2. outgoing calls — what does it lean on to decide?
--  3. the IsPodForwarded entry looks like the decider: pick it in quickfix
--     (lands on the call site), then gd into watch/forwarders.go:57.
--  4. note it: this is the real check.
--  5. incoming calls on IsPodForwarded — who else asks "is it forwarded?"
--  6. one of those callers is not the pod view: peek at it (pick in quickfix).
--  7. <C-o> back to IsPodForwarded — seen enough of the sibling.
--  8. <C-o> again, back up to portForwardIndicator.
--  9. incoming calls on portForwardIndicator — who installs the decorator?
-- 10. pick NewPod (view/pod.go:50, the one caller).
-- 11. note it: SetDecorateFn wires the indicator.
-- 12. gd on p.portForwardIndicator in NewPod — lands back on the root: the
--     code forms a loop NewPod → portForwardIndicator, which should draw as a
--     back-edge.
-- Left unexplored on purpose: the other callees of the root, the other
-- callers of IsPodForwarded.
local D = dofile(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h') .. '/drive.lua')
local POD, FWD = 'internal/view/pod.go', 'internal/watch/forwarders.go'

D.begin('portforward')

-- 1. the error line
D.go(POD, 66, '%) ()portForwardIndicator%(')
D.ready()
D.step('open portForwardIndicator (error line)')

-- 2. what does it call?
local q = D.ask(vim.lsp.buf.outgoing_calls)
D.step('outgoing calls from portForwardIndicator')

-- 3. IsPodForwarded is the decider: pick its call site, gd into it
D.pick(q, function(it) return it.text == 'IsPodForwarded' end, 'IsPodForwarded call site')
D.ask(vim.lsp.buf.definition)
D.step('gd into IsPodForwarded')

-- 4. note
D.note('the real check: prefix match on fqn + "|"')
D.step('note on IsPodForwarded')

-- 5. who else asks?
D.aim(57, 'Forwarders%) ()IsPodForwarded')
q = D.ask(vim.lsp.buf.incoming_calls)
D.step('incoming calls on IsPodForwarded')

-- 6. peek at a sibling caller that is not the pod view
D.pick(q, function(it, file) return it.text ~= 'portForwardIndicator' end, 'non-pod caller')
D.step('peek at a sibling caller')

-- 7. back to IsPodForwarded
D.back()
D.step('<C-o> back to IsPodForwarded')

-- 8. back up to the root (the jump list holds the qf pick and the gd)
D.go(POD, 66, '%) ()portForwardIndicator%(')
D.step('back up to portForwardIndicator')

-- 9. who installs the decorator?
q = D.ask(vim.lsp.buf.incoming_calls)
D.step('incoming calls on portForwardIndicator')

-- 10. NewPod
D.pick(q, function(it) return it.text == 'NewPod' end, 'NewPod')
D.step('jump to NewPod')

-- 11. note
D.note('SetDecorateFn wires the indicator')
D.step('note on NewPod')

-- 12. gd on the method value: lands back on the root (loop)
D.aim(61, 'p%.()portForwardIndicator')
D.ask(vim.lsp.buf.definition)
D.step('gd p.portForwardIndicator from NewPod (loop)')

D.finish()
