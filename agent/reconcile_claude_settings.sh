#!/usr/bin/env bash
# Reconcile the rendered ~/.claude/settings.json with its agent-config sources.
#
# Claude Code writes to the rendered file (/config, `claude plugin enable`,
# "always allow" on a permission prompt), so it drifts from agent-config. Default
# mode shows the drift and exits 1 if any. --apply ports every changed leaf back
# into agent-config/settings.json (arrays: added items appended, removed items
# dropped) and re-renders. It never edits settings.work.json: if a change is
# work-only, move it there by hand afterwards and re-run.
set -uo pipefail

CONFIG="${AGENT_CONFIG:-$HOME/dotfiles/agent-config}"
RENDERED="$HOME/.claude/settings.json"
here=$(cd "$(dirname "$0")" && pwd)
apply=0
[ "${1:-}" = --apply ] && apply=1

if [ -L "$RENDERED" ]; then
  echo "FAIL  $RENDERED is a symlink; run claude/setup_claude.sh to switch to rendering" >&2; exit 1
fi
if [ ! -f "$RENDERED" ]; then
  echo "FAIL  $RENDERED missing; run claude/setup_claude.sh" >&2; exit 1
fi

expected=$("$here/render_claude_settings.sh") || exit 1
if cmp -s <(jq -S . <<<"$expected") <(jq -S . "$RENDERED"); then
  echo "ok    $RENDERED in sync with agent-config"; exit 0
fi

echo "drift (- rendered from agent-config, + what Claude Code has now):"
diff -u --label expected --label actual <(jq -S . <<<"$expected") <(jq -S . "$RENDERED") | tail -n +3
[ "$apply" = 1 ] || { echo; echo "re-run with --apply to port this into $CONFIG/settings.json"; exit 1; }

src="$CONFIG/settings.json"
jq --argjson exp "$expected" --slurpfile act "$RENDERED" '
  def leaves($p): if type == "object" and length > 0
    then to_entries[] | .key as $k | .value | leaves($p + [$k])
    else {path: $p, value: .} end;
  $act[0] as $act
  | [$act | leaves([])] as $A | [$exp | leaves([])] as $E
  | reduce $A[] as $l (.;
      ($exp | getpath($l.path)) as $e
      | if $e == $l.value then .
        elif ($l.value | type) == "array" and ($e | type) == "array"
          then setpath($l.path; ((getpath($l.path) // []) + ($l.value - $e)) - ($e - $l.value))
        else setpath($l.path; $l.value) end)
  | reduce ($E[] | select(. as $l | ($act | getpath($l.path)) == null and $l.value != null)) as $l (.; delpaths([$l.path]))
' "$src" > "$src.tmp" && mv "$src.tmp" "$src" || { rm -f "$src.tmp"; exit 1; }

"$here/render_claude_settings.sh" > "$RENDERED.tmp" && mv "$RENDERED.tmp" "$RENDERED"
echo "ported into $src and re-rendered; review with: git -C $CONFIG diff settings.json"
