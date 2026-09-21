#!/usr/bin/env bash
# Prints the content of ~/.claude/settings.json to stdout.
#
# Claude Code reads exactly one user-scope file, ~/.claude/settings.json; there
# is no user-level settings.local.json. So machine-specific config can't live in
# a side file — it has to be baked into that one file. This renders it:
#   agent-config/settings.json                      always
#   agent-config/settings.work.json  merged on top  when ~/.dotfiles-profile says `work`
# Merge: objects recurse, arrays union, scalars — work wins. The literal string
# `$HOME` inside any value is replaced with the real home dir, so sources can
# hold machine-independent absolute paths (Claude Code does not expand ~ there).
set -euo pipefail

CONFIG="${AGENT_CONFIG:-$HOME/dotfiles/agent-config}"
PROFILE_FILE="${DOTFILES_PROFILE_FILE:-$HOME/.dotfiles-profile}"

profile=$(cat "$PROFILE_FILE" 2>/dev/null || true)
if [ "$profile" != work ]; then
  jq . "$CONFIG/settings.json"
  exit 0
fi

jq -s '
  def merge($a; $b):
    reduce ($b | keys_unsorted[]) as $k ($a;
      if ($a[$k] | type) == "object" and ($b[$k] | type) == "object" then .[$k] = merge($a[$k]; $b[$k])
      elif ($a[$k] | type) == "array" and ($b[$k] | type) == "array" then .[$k] = ($a[$k] + $b[$k] | unique)
      else .[$k] = $b[$k] end);
  merge(.[0]; .[1])
  | walk(if type == "string" then gsub("\\$HOME"; $home) else . end)
' --arg home "$HOME" "$CONFIG/settings.json" "$CONFIG/settings.work.json"
