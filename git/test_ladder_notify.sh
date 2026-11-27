#!/usr/bin/env bash
# Tests bin/ladder-notify (the global hook.ladder-follow reference-transaction
# hook) with real commits in a scratch two-worktree ladder repo. No nvim.
#   git/test_ladder_notify.sh
set -uo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
hook="$here/bin/ladder-notify"
tmp=$(mktemp -d)
fails=0

g() { git -c commit.gpgsign=false -c hook.ladder-follow.event=reference-transaction \
  -c "hook.ladder-follow.command=$hook" "$@"; }
commit() { echo "$3" >>"$1/$2"; g -C "$1" add "$2"; g -C "$1" commit -qm "$3"; }
settle() { for _ in $(seq 1 30); do [ "$(git -C "$1" rev-parse HEAD)" = "$2" ] && return; sleep 0.1; done; }
check() { # name, got, want
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 — got $2, want $3"; fails=$((fails + 1)); fi
}

review="$tmp/review" agent="$tmp/review-agent"
g init -q -b main "$review"
commit "$review" base.txt base
g -C "$review" switch -qc rung1; commit "$review" one.txt r1
g -C "$review" switch -qc fat; commit "$review" fat.txt f1
g -C "$review" switch -q --detach rung1
g -C "$review" worktree add -q "$agent" fat
mkdir -p "$review/.git/ladders"; echo '{}' >"$review/.git/ladders/fat.json"
follow_file="$review/.git/ladder-follow"

# Not following: an agent commit leaves the review worktree alone.
before=$(git -C "$review" rev-parse HEAD)
commit "$agent" fat.txt f2; sleep 0.5
check "not following: untouched" "$(git -C "$review" rev-parse HEAD)" "$before"

# Following fat: the agent's commit moves the review worktree to the new tip.
g -C "$review" checkout -q --detach fat
printf 'fat\n\n' >"$follow_file"
commit "$agent" fat.txt f3
tip=$(git -C "$review" rev-parse fat); settle "$review" "$tip"
check "following: review at new fat tip" "$(git -C "$review" rev-parse HEAD)" "$tip"
check "following: still detached" "$(git -C "$review" symbolic-ref -q HEAD || echo detached)" detached
check "agent: still attached to fat" "$(git -C "$agent" symbolic-ref --short HEAD)" fat

# Dirty tracked file: left alone.
echo wip >>"$review/fat.txt"
before=$(git -C "$review" rev-parse HEAD)
commit "$agent" fat.txt f4; sleep 0.5
check "dirty: untouched" "$(git -C "$review" rev-parse HEAD)" "$before"
git -C "$review" checkout -q -- fat.txt

# You moved elsewhere: left alone.
g -C "$review" checkout -q --detach rung1
commit "$agent" fat.txt f5; sleep 0.5
check "moved away: untouched" "$(git -C "$review" rev-parse HEAD)" "$(git -C "$review" rev-parse rung1)"

# Following a rung: a cascade-style move (throwaway worktree) is followed.
printf 'rung1\nmain\n' >"$follow_file"
g -C "$review" worktree add -q "$tmp/op" rung1
commit "$tmp/op" one.txt r1-late
g -C "$review" worktree remove "$tmp/op"
tip=$(git -C "$review" rev-parse rung1); settle "$review" "$tip"
check "rung: review at new rung tip" "$(git -C "$review" rev-parse HEAD)" "$tip"

# Your edits, absorbed by the agent: the tree matches the new tip, so the
# hook re-points HEAD and you come back clean — untracked new files included.
echo "review edit" >>"$review/one.txt"; echo "new file" >"$review/new.txt"
g -C "$review" worktree add -q "$tmp/op" rung1
cp "$review/one.txt" "$review/new.txt" "$tmp/op/"
g -C "$tmp/op" add one.txt new.txt; g -C "$tmp/op" commit -qm "absorb review edits"
g -C "$review" worktree remove "$tmp/op"
tip=$(git -C "$review" rev-parse rung1); settle "$review" "$tip"
check "absorbed: review at new tip" "$(git -C "$review" rev-parse HEAD)" "$tip"
check "absorbed: tree clean" "$(git -C "$review" status --porcelain)" ""
check "absorbed: edit kept on disk" "$(tail -n1 "$review/one.txt")" "review edit"

# Partly absorbed (tree differs from the new tip): left alone.
echo "keep" >>"$review/one.txt"; echo "other" >>"$review/base.txt"
before=$(git -C "$review" rev-parse HEAD)
g -C "$review" worktree add -q "$tmp/op" rung1
cp "$review/one.txt" "$tmp/op/"; g -C "$tmp/op" commit -qam "absorb only one.txt"
g -C "$review" worktree remove "$tmp/op"; sleep 0.5
check "partial: HEAD untouched" "$(git -C "$review" rev-parse HEAD)" "$before"
check "partial: edits untouched" "$(tail -n1 "$review/base.txt")" "other"
git -C "$review" checkout -q -- one.txt base.txt

# A repo with no ladder: exits at once, does nothing.
plain="$tmp/plain"; g init -q -b main "$plain"
start=$(perl -MTime::HiRes=time -e 'print time')
(cd "$plain" && printf '0 1 refs/heads/main\n' | "$hook" committed); rc=$?
ms=$(perl -MTime::HiRes=time -e "print int((time - $start) * 1000)")
check "no ladder: exit 0" "$rc" 0
check "no ladder: under 200ms" "$([ "$ms" -lt 200 ] && echo yes || echo "no (${ms}ms)")" yes

trash "$tmp" 2>/dev/null || true
echo "$fails failed"
[ "$fails" -eq 0 ]
