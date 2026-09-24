# spelunk k9s scenarios — findings

Run: `XDG_CONFIG_HOME=<cfg> nvim/probes/spelunk/scenarios/run.sh` (k9s @ `61851153`,
nvim 0.12.4, gopls). Dumps next to this file (git-ignored): `<name>.tree.txt`
(the split), `<name>.md` (the export), `<name>.log` (narrated steps with
`current=` / `frontier=` after each). Findings only; nothing under `nvim/lua/`
was changed. Quick picks are `:cc N` on the list the builtin filled (same
landing as `:edit` + cursor, and it feeds the jumplist, so `<C-o>` works).

Headline: the *capture* works — every visit registered, `<C-o>` retreats added
no edges, notes landed, the frontier left where it was. The *reading* doesn't
hold yet: at 40 cols the marker and notes are off-screen, and most `↩` lines
are echoes of edges already in the tree rather than loops.

## portforward — "the PF column says not forwarded: who decides?"

Auto-started by the first outgoing-calls request (no `:SpelunkStart`).

```
portForwardIndicator          view/pod.go:66            > YOU ARE HERE
├─→ IsPodForwarded            watch/forwarders.go:57    note: the real check: prefix match on fqn + "|"
│   ├─↩ portForwardIndicator                            (loop)
│   ├─← showPFCmd             view/pf_extender.go:68
│   └─? 1 unexplored callers
├─← NewPod                    view/pod.go:50            note: SetDecorateFn wires the indicator
│   └─↩ portForwardIndicator                            (loop)
├─? RowsRange                 model1/table_data.go:98   callee
…4 more pending callees
```

- Mostly the shape I'd draw, and it's easy to read. Frontier held up: 6 → 5
  after the gd, 7 after incoming calls, 6 again after `<C-o>`. It matches the
  tree (5 callees + 1 caller).
- **Both `(loop)` lines are junk.** `IsPodForwarded ├─↩ portForwardIndicator` is
  the incoming-calls answer naming the parent you came down from. `NewPod └─↩
  portForwardIndicator` is gd from NewPod back to the node whose caller it is.
  Each one is a tree edge drawn a second time, backwards. k9s has no real cycle
  here, so the note's "loop back to NewPod" can only ever be an echo.
- **Altitude.** NewPod calls the root, but it is drawn as a child under it
  (`├─← NewPod`). The design mock puts NewPod on the top line. The `←` glyph
  carries the direction, but the tree grows downward in both directions.

## dispatch — "`:pods` shows the wrong view: how does a command become a view?"

```
run                    internal/view/command.go:141   > YOU ARE HERE
├─← gotoResource       internal/view/app.go:693
│   ├─← gotoCmd        internal/view/app.go:630       note: the : prompt Enter handler; dispatch starts here
│   └─? 10 unexplored callers
├─← exec               internal/view/command.go:298
│   ├─↩ run                                           (loop)
│   ├─→ inject         internal/view/app.go:700
│   │   └─→ Init       internal/model/types.go:57
│   │       ├─↩ Init                                  (loop)
│   │       ├─→ Init   internal/view/browser.go:61    note: :pods lands in the generic Browser
│   │       └─? 17 unexplored implementations
│   └─? 18 unexplored callees
├─? defaultCmd         internal/view/command.go:199   caller
…19 in-repo pending callees, then:
├─? Msg                /Users/mat/go/pkg/mod/github.com/rs/zerolog@v1.32.0/event.go:106  callee
├─? Msgf / Err / Debug / Error                        (zerolog, same)
└─? New                /opt/homebrew/Cellar/go/1.26.7/libexec/src/errors/errors.go:64  callee
```

- Both halves are there: up (run ← gotoResource ← gotoCmd) and down (exec →
  inject → Init → Browser.Init). `exec ├─↩ run (loop)` is the one **real**
  back-edge in the whole run, from exec's recover() path calling run again.
  Good.
- **`← exec` has the wrong glyph.** I reached exec by outgoing calls + gd, which
  is a step down, but it draws as a caller. It was first listed as a pending
  *caller* of run (the two call each other), and that first entry is the one
  the visit consumed, so it sets the glyph. The gd's `def` entry does not.
- **Phantom current.** Running `gi` on `c.Init` inside inject made
  `Init internal/model/types.go:57` (the Component interface method) a node
  *and the current one*. The cursor never left app.go:702, but the step log says
  `step 12 … current=Init@internal/model/types.go:57`. The export has
  `inject -->|jump| Init` for a jump that never happened.
- **Self-loop junk.** `Init ├─↩ Init (loop)`: gopls lists the interface method
  itself among its implementations, and it gets drawn as a loop onto itself
  (`n202b78020f -.->|impl| n202b78020f` in the mermaid block).
- **Out-of-repo callees.** zerolog `Msg/Msgf/Err/Debug/Error` and `errors.New`
  are 6 of the 25 pending root lines. Their absolute paths also break the
  common-prefix trim: this tree shows `internal/view/…` while the other two
  drop `internal/`.
- **Wall of pending lines.** With run as the current node, all 25 of its pending
  callees expand one per line, 37 lines in total. The explored shape is the top
  12.
- The last step jumped back up to run, which is an ancestor, so no edge was
  added (by design). The back-edge the note asked for comes from the code
  (exec → run), not from the navigation.

## daomodel — "empty pod list: where does model ask dao, and is Pod.List what runs?"

```
List               dao/pod.go:80
├─→ List           dao/types.go:69            note: the dao contract every resource implements
│   ├─↩ List                                  (loop)
│   ├─→ List       dao/generic.go:40          note: fallback for resources without a typed dao
│   │   ├─← check  model/pulse_health.go:103
│   │   └─? 2 unexplored callers
│   ├─↩ List                                  (loop)
│   ├─↩ check                                 (loop)
│   ├─← list       model/pulse.go:92          > YOU ARE HERE  note: model asks dao for rows here
│   ├─? 23 unexplored implementations
│   └─? 12 unexplored callers
└─? 1 unexplored implementations
```

- **Unreadable.** There are four nodes named `List` and two `↩ List` lines with
  no path, so you can't tell which List either one points at. The first is Pod.List (the root)
  listed among Lister.List's implementations: another echo. The second is the
  root again, via `gr`, because `p.Resource.List` at dao/pod.go:81 sits inside
  it. Neither the tree nor the mermaid (`["List"]` ×3) says which List is which.
  The receiver type (`(*Pod)`) is stripped for keying and never comes back for
  display.
- **Impl altitude.** `gi` on a concrete method returns the interface it
  satisfies, which is drawn as `→ List dao/types.go:69`, down the stack. The
  abstraction is the parent in my head. The root's `└─? 1 unexplored
  implementations` is not an implementation at all: it is the *other interface*
  Pod.List satisfies (`internal/model/types.go:106`).
- **`(loop)` labels convergence.** `↩ check (loop)` is check being named again,
  by gr on Lister.List, after it was visited as a caller of Generic.List. That
  is two paths meeting (convergence), not a cycle, but it gets the same label
  as exec → run.
- **Pending counts don't match the frontier.** The `?` lines sum to 38, but
  `frontier()` says 32 (`step 14 … frontier=32`). Job.List, for example, is
  pending both as an implementation and as a gr caller, and is counted once per
  edge. dispatch has the same gap: 70 rendered, 65 in the frontier.
- It did land on the boundary: `← list model/pulse.go:92` is the model-side call
  through the Lister interface.

## Across all three

- **At 40 cols the marker and notes are invisible.** `> YOU ARE HERE` starts at
  col 56 (portforward), 54 (dispatch) and 46 (daomodel). 11/12, 35/37 and 7/12
  lines run past 40 cols. The split is `nowrap`, and its cursor follows the
  node it was on, not the current one. So "where am I", half of the
  hypothesis, is off-screen without `zl`.
- Visit detection never missed: every `:cc`, gd and `:edit` landing changed
  `current`, and every `<C-o>` to an ancestor added no edge.
- The public API was enough for the step log (`graph():current()`,
  `graph():frontier()`, `name()`, `export_path()`). No accessor is missing.

## Fix first (ranked)

1. **Make "where am I" visible at 40 cols.** Put the marker in the left gutter
   (`>` before the branch glyphs, or a sign), move the split cursor onto the
   current node on every render, and drop notes to a second line or a
   hover/float. Today the marker sits at col 46–56 of a 40-col nowrap split.
2. **Stop drawing echoes as loops.** Don't add an entry that points at the
   from-node's own tree parent (the incoming-calls answer that names where you
   came from, or gd back to the node you were the caller of), and don't add one
   that points at the from-node itself (`↩ Init` → Init). That removes 5 of the
   7 `↩` lines in this run. The two left are `exec ↩ run` (a real cycle) and
   `↩ check` (convergence).
3. **Give every line an identity.** Put the path on `↩` lines, and show the
   receiver in names (`Pod.List`, `Generic.List`) while keying on the bare
   name. Label cycles (the target is an ancestor) separately from convergence
   (the target is elsewhere in the tree).
4. **Keep out-of-repo symbols out of the frontier.** Drop the per-line entries
   for callees whose path is outside the client root, and replace them with one
   `? N external` line. Compute the common-dir trim over in-root paths only.
5. **Draw the glyph from the edge actually walked, and don't move current
   without a jump.** `← exec` should be `→ exec` after a gd. gi/gr from inside a
   function should not make the identifier's definition the current node (the
   phantom `Init@model/types.go:57`).

Also seen, lower priority: callers render below their callee (`← NewPod` under
the root); an impl edge from concrete to interface reads as "down"; `?` counts
double-count a sym pending under two edges (38 vs 32); a current node with 25+
pending children floods the split.

## Deviations from the seeds

- dispatch: `App.gotoCmd` (app.go:630) is not a direct caller of `run`. It
  calls `gotoResource` (app.go:694), which calls run. Added that hop, and picked
  the app.go entry explicitly: six views define a `gotoCmd`, and actions.go
  comes first in the list.
- dispatch: "follow comp into a concrete view" became gd `inject` → gi `c.Init`
  → Browser.Init. "Back up to run" is a jump to an ancestor, and by design that
  draws no edge. The back-edge comes from exec's outgoing calls listing run.
- daomodel: "gr/gd on the interface method it satisfies" became `gi` on
  Pod.List. gopls returns the interfaces it satisfies (dao Lister.List plus
  model/types.go:106), and gd on a method declaration just returns the declaration.
- portforward: no cycle exists, so "loop back to NewPod" is gd on
  `p.portForwardIndicator` inside NewPod, and it renders as an echo (see above).
- Every seed line behaved as given at `61851153`.
