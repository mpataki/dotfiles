# nvim PR review comments — design

Date: 2026-09-22

## Goal

Write GitHub PR review comments from inside nvim, on top of the existing
mini.diff overlay + telescope review flow, without moving the review verdict
into the terminal. Comments accumulate locally, push into a **pending** GitHub
review, and Mat scans and submits the review in the browser.

Secondary: read everyone else's comments in the editor, and fix the review
flow's existing rough edges (PR identity guessed from `main`/`master`,
merge-base logic duplicated 3x, cwd-relative path bug).

## Non-goals (v1)

- Submitting a review verdict (approve / request changes) from nvim.
- Replying to existing threads. Replies bypass the pending review and go live
  immediately.
- Comments on deleted lines (`side=LEFT`). Overlay renders deletions as
  virtual text with no cursor line; v1 anchors `RIGHT` only.
- Comments on lines outside the diff. GitHub refuses them; reading the rest of
  the repo for context is already solved by being in nvim.
- Merging browser edits to the pending review with local edits. Push and pull
  are each explicit overwrites; a guard stops silent clobbering.

## Existing pieces (kept)

- `nvim/lua/mpataki/plugins/minidiff.lua` — `DiffPRBase` sets mini.diff ref to
  merge-base per buffer; `<leader>go` overlay.
- `nvim/lua/mpataki/plugins/diffview.lua` — `DiffviewPR`, `<leader>ge` exit to file.
- `nvim/lua/mpataki/plugins/telescope.lua` — `<leader>gS` PR files picker.
- `nvim/lua/mpataki/plugins/gitlinker.lua` — repo-from-buffer-dir pattern.

## Architecture

New module tree `nvim/lua/mpataki/review/` (each file < 500 LOC):

| file | responsibility | depends on |
|------|----------------|------------|
| `pr.lua` | PR identity: repo root, owner/repo, number, base ref, head SHA, merge-base. One helper replaces the 3 merge-base snippets. | `git`, `gh` |
| `store.lua` | Pending comments file: parse / serialize / add / update / delete. Pure. | fs |
| `gh.lua` | GitHub calls via `gh api`: fetch threads, fetch my pending review, delete pending, create pending. Runner injectable so tests use a fake. | `gh` |
| `render.lua` | Extmarks (virtual lines) for pending + remote comments; quickfix population. | store, gh cache |
| `capture.lua` | Anchored float editor for one comment. | store, render |
| `init.lua` | User commands, keymaps, wiring. | all |

`plugins/minidiff.lua`, `plugins/diffview.lua`, `plugins/telescope.lua` call
`review.pr` for base/merge-base instead of inlining the shell snippet.

## PR identity (`pr.lua`)

- Root: `git -C <buffer dir> rev-parse --show-toplevel`. All paths sent to git
  or GitHub are relative to this, never to nvim's cwd. Fixes
  `minidiff.lua:50` (`fnamemodify(':.')` is cwd-relative; `git show sha:path`
  needs repo-relative).
- Common dir: `git rev-parse --git-common-dir` (shared across worktrees).
- PR: `gh pr view --json number,baseRefName,headRefOid,url` run with cwd =
  root. Cached per root for the session; `:ReviewRefresh` clears.
- Base: `git merge-base HEAD origin/<baseRefName>`. Fallback when no PR:
  current `main`/`master` guess (existing behavior).
- `DiffPRBase` and `DiffviewPR` and the PR files picker all take base from here.

## Comments file (`store.lua`)

Path: `<git-common-dir>/reviews/<pr-number>.md`. Out of tree, shared by all
worktrees of the repo, same location pattern as `ladders/*.json`.

Format (markdown, hand-editable escape hatch):

```markdown
<!-- review: owner/repo#123 head=<sha> pushed=<fingerprint> -->

## path/to/file.go:42

Body text, markdown, may span lines.

## path/to/other.go:10-15

Range comment: start_line=10, line=15.
```

- Header comment carries head SHA at last push and the fingerprint of what
  was pushed (see guard).
- Entries keyed by `path:line` (or `path:start-end`). One entry per anchor.
- Empty body on save deletes the entry.

Remote threads are cached separately as JSON at
`<git-common-dir>/reviews/<pr-number>.remote.json`. Never hand-edited.

## GitHub calls (`gh.lua`)

All via `gh api` with cwd = repo root so `{owner}/{repo}` placeholders resolve.

- Threads: `GET repos/{owner}/{repo}/pulls/N/comments --paginate` → id, path,
  line, side, start_line, body, user.login, in_reply_to_id, html_url.
- My pending review: `GET .../pulls/N/reviews`, filter `state == PENDING` and
  `user.login == me`; then `GET .../reviews/{id}/comments`.
- Delete pending: `DELETE .../reviews/{id}`.
- Create pending: `POST .../reviews` with `commit_id`, `comments[]` of
  `{path, line, side: RIGHT, start_line?, start_side?, body}`, **no `event`**.
  JSON via `--input -`.

Runner is a function `(argv, cwd) -> (code, stdout, stderr)` injected at module
level; the fake used in probes returns canned JSON and records calls.

## Commands and keymaps

| command | does |
|---------|------|
| `:ReviewComment` (`<leader>gc`, n + v) | Open capture float at cursor / selection. Reopens existing pending entry if one is anchored here. |
| `:ReviewPull` | Fetch threads + my pending review → rewrite `.remote.json`, rewrite pending section of `.md` from server, re-render. |
| `:ReviewPush[!]` | Guards, then delete pending + create pending from `.md`. `!` skips the clobber guard. Prints PR URL bare. |
| `:ReviewRender` | Re-render extmarks + quickfix for current buffer from local files. Also runs on `BufEnter` when a review file exists for the PR. |
| `:ReviewQuickfix` | Populate quickfix with pending + remote comments, `:copen`. |
| `:ReviewOpen` | Edit the `.md` escape hatch. |

Push guards, in order, each with an actionable message:

1. Not in a PR branch → stop.
2. Local `HEAD != headRefOid` → stop (line numbers would drift).
3. Server pending review fingerprint ≠ `pushed=` in header → stop unless `!`.
   Fingerprint = sha256 of sorted `path:line:body` list.
4. Any entry's line outside the diff hunks vs merge-base → stop, name the
   entry (GitHub would reject the whole batch).

## Capture float (`capture.lua`)

- `nvim_open_win` relative to cursor, below the line, ~60 cols × 6 rows,
  `filetype=markdown`, scratch buffer, enters insert mode.
- `:w` / `<C-s>` → `store.upsert`, close, re-render. `q` (normal) → close, no
  change. Buffer-local mappings only.
- Visual selection → range anchor.
- Refuses with a notify when the cursor line is not inside a diff hunk
  (uses mini.diff hunk data for the buffer).

## Rendering (`render.lua`)

- One namespace. Virtual lines below the anchored line: pending in
  `ReviewPending` highlight (default links to `DiagnosticVirtualTextWarn`),
  remote in `ReviewRemote` (links to `Comment`), prefixed `@author`.
- Quickfix: one item per comment, text = `[@author] first line of body`,
  pending entries marked `[pending]`.

## Errors

`vim.notify` at ERROR with the failing command name and the first line of
`gh` stderr. No silent fallbacks; the existing "file didn't exist at base"
path in `minidiff.lua:53` stays but only after the path is repo-relative.

## Testing (nvim-probe)

Probes under `nvim/probes/review/`, run with
`nvim --headless -c 'luafile <probe>' -c 'qa'`.

- Tier 2: `store` parse ⇄ serialize round trip, upsert/delete, range parsing.
- Tier 2: `pr` root + relative-path resolution from a subdirectory cwd
  (regression for the cwd bug).
- Tier 2: push guard decisions with a fake `gh` runner (head mismatch,
  fingerprint mismatch, out-of-hunk line).
- Tier 3: `:ReviewComment` opens a float, writing + `:w` produces an entry in
  the file and an extmark in the buffer; `q` produces neither.
- Tier 3: `:ReviewQuickfix` lists pending + cached remote items.

Real `gh` calls are exercised manually against a real PR before handoff.

## Out of scope but noted

- `side=LEFT` via mini.diff hunk data.
- Replies (GraphQL `addPullRequestReviewThreadReply` into the pending review).
- Submitting from nvim once the anxiety is gone: one more `event` field.

## Usage

1. `gh pr checkout N` (or a worktree on the PR branch), open nvim there.
2. `<leader>gS` picks a PR file; `<leader>go` for overlay.
3. `<leader>gc` on a changed line (or a visual range) opens the float. `:w` saves, `q` cancels. Empty body deletes.
4. `:ReviewPull` fetches everyone's threads and your pending review; comments render as virtual lines, `<leader>gC` lists them in quickfix.
5. `:ReviewPush` creates/replaces your pending review on GitHub. Finish in the browser.
6. Escape hatch: `:ReviewOpen` edits `<git-common-dir>/reviews/<N>.md` directly.

`:ReviewRefresh` clears the cached PR identity and re-renders — use it after a
rebase, or when the PR is opened mid-session. `:ReviewPush!` skips the clobber
guard (push over a pending review that differs from what was last pushed).
