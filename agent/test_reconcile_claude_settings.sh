#!/usr/bin/env bash
# Round-trip test for render + reconcile against a throwaway HOME and config copy.
# Scenario: Claude Code adds an allow, drops another, enables a plugin, changes a
# scalar and deletes a key in the rendered file; --apply must port all of it into settings.json, leave the
# work-only allows out of it, and leave the rendered file in sync afterwards.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/home/.claude" "$tmp/cfg"
cp "$here/../agent-config/settings.json" "$here/../agent-config/settings.work.json" "$tmp/cfg/"
export HOME="$tmp/home" AGENT_CONFIG="$tmp/cfg" DOTFILES_PROFILE_FILE="$tmp/profile"
echo work > "$tmp/profile"

fail() { echo "FAIL: $*" >&2; exit 1; }

"$here/render_claude_settings.sh" > "$HOME/.claude/settings.json"
"$here/reconcile_claude_settings.sh" >/dev/null || fail "fresh render reported drift"

removed=$(jq -r '.permissions.allow[0]' "$AGENT_CONFIG/settings.json")
jq --arg r "$removed" '.permissions.allow -= [$r] | .permissions.allow += ["Bash(made-up-tool:*)"]
  | .enabledPlugins["fake@nowhere"] = true | .model = "test-model" | del(.editorMode)' \
  "$HOME/.claude/settings.json" > "$tmp/mut" && mv "$tmp/mut" "$HOME/.claude/settings.json"
"$here/reconcile_claude_settings.sh" >/dev/null && fail "drift not detected"

"$here/reconcile_claude_settings.sh" --apply >/dev/null || fail "--apply failed"
jq -e '.permissions.allow | index("Bash(made-up-tool:*)")' "$AGENT_CONFIG/settings.json" >/dev/null || fail "allow not ported"
jq -e '.enabledPlugins["fake@nowhere"] == true' "$AGENT_CONFIG/settings.json" >/dev/null || fail "plugin not ported"
jq -e '.model == "test-model"' "$AGENT_CONFIG/settings.json" >/dev/null || fail "scalar not ported"
jq -e --arg r "$removed" '.permissions.allow | index($r) == null' "$AGENT_CONFIG/settings.json" >/dev/null || fail "removed allow not dropped"
jq -e 'has("editorMode") | not' "$AGENT_CONFIG/settings.json" >/dev/null || fail "deleted key not dropped"
jq -e '.permissions.allow | index("Bash(acli jira board:*)") == null' "$AGENT_CONFIG/settings.json" >/dev/null || fail "work-only allow leaked into settings.json"
jq -e '.enabledPlugins["work@mat-local"] == null' "$AGENT_CONFIG/settings.json" >/dev/null || fail "work plugin leaked into settings.json"
cmp -s <(jq -S . "$AGENT_CONFIG/settings.work.json") <(jq -S . "$here/../agent-config/settings.work.json") || fail "settings.work.json was modified"
"$here/reconcile_claude_settings.sh" >/dev/null || fail "still drifted after --apply"
echo "ok    reconcile round-trip"
