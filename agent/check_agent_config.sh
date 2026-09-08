#!/usr/bin/env bash
# Doctor for the multi-harness agent config. Read-only; exits 1 if anything is off.
#
# Checks that both harnesses resolve to the claude-config sources:
#   Claude: ~/.claude/{CLAUDE.md,settings.json,skills,agents,commands,workflows} links
#   Codex:  ~/.codex/AGENTS.md link, rendered AGENTS.md/agents up to date with their
#           sources, one link per skill in ~/.agents/skills, agent role links,
#           MCP servers from mcp-servers.json registered, config.toml parses,
#           signing env keys present.
set -uo pipefail

CONFIG="$HOME/dotfiles/claude-config"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
AGENT_SKILLS="$HOME/.agents/skills"
fail=0

ok()   { printf '  ok    %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; fail=1; }
warn() { printf '  warn  %s\n' "$1"; }

check_link() { # dst expected-src   (trailing slashes ignored on both sides)
  local dst=$1 src=${2%/} actual
  actual=$(readlink "$dst" 2>/dev/null); actual=${actual%/}
  if [ -L "$dst" ] && [ "$actual" = "$src" ] && [ -e "$dst" ]; then ok "$dst -> $src"
  elif [ -L "$dst" ] && [ ! -e "$dst" ]; then bad "$dst is a broken link ($actual)"
  elif [ -L "$dst" ]; then bad "$dst -> $actual (wanted $src)"
  elif [ -e "$dst" ]; then bad "$dst exists but is not a link (unmanaged)"
  else bad "$dst missing"; fi
}

echo "Claude Code"
for f in CLAUDE.md settings.json; do check_link "$HOME/.claude/$f" "$CONFIG/$f"; done
for d in skills agents commands workflows; do check_link "$HOME/.claude/$d" "$CONFIG/$d"; done
jq -e . "$CONFIG/settings.json" >/dev/null 2>&1 && ok "settings.json parses" || bad "settings.json does not parse"

echo "Codex"
if ! command -v codex >/dev/null 2>&1; then
  warn "codex CLI not installed; skipping"
else
  check_link "$CODEX_HOME/AGENTS.md" "$CONFIG/codex/AGENTS.md"
  check_link "$CODEX_HOME/hooks.json" "$CONFIG/codex/hooks.json"
  tmp=$(mktemp -d)
  python3 "$CONFIG/codex/render-agents-md.py" "$CONFIG/CLAUDE.md" "$tmp/AGENTS.md" \
    && cmp -s "$tmp/AGENTS.md" "$CONFIG/codex/AGENTS.md" && ok "codex/AGENTS.md is current with CLAUDE.md" \
    || bad "codex/AGENTS.md is stale or the mapping broke — run codex/setup_codex.sh"
  python3 "$CONFIG/codex/render-agent-roles.py" "$CONFIG/agents" "$tmp/agents" \
    && diff -rq "$tmp/agents" "$CONFIG/codex/agents" >/dev/null 2>&1 && ok "codex/agents/*.toml current with agents/*.md" \
    || bad "codex/agents/*.toml stale — run codex/setup_codex.sh"
  rm -rf "$tmp"
  for d in "$CONFIG"/skills/*/; do
    n=$(basename "$d"); check_link "$AGENT_SKILLS/$n" "${d%/}"
  done
  for d in "$AGENT_SKILLS"/*/; do
    n=$(basename "$d"); [ -L "${d%/}" ] || warn "$AGENT_SKILLS/$n is a real directory (local, unmanaged)"
  done
  for f in "$CONFIG"/codex/agents/*.toml; do
    check_link "$CODEX_HOME/agents/$(basename "$f")" "$f"
  done
  python3 -c "import tomllib,sys; tomllib.load(open(sys.argv[1],'rb'))" "$CODEX_HOME/config.toml" 2>/dev/null \
    && ok "config.toml parses" || bad "config.toml does not parse"
  registered=$(codex mcp list 2>/dev/null | awk 'NR>1{print $1}')
  for n in $(jq -r 'keys[] | select(. != "codex")' "$CONFIG/mcp-servers.json"); do
    echo "$registered" | grep -qx "$n" && ok "codex MCP registered: $n" || bad "codex MCP missing: $n"
  done
  python3 - "$CODEX_HOME/config.toml" <<'EOF' && ok "signing env keys present in shell_environment_policy.set" || bad "signing env keys missing from shell_environment_policy.set"
import sys, tomllib
c = tomllib.load(open(sys.argv[1], 'rb')).get('shell_environment_policy', {}).get('set', {})
sys.exit(0 if c.get('GIT_CONFIG_COUNT') == '2' and 'GIT_CONFIG_KEY_1' in c else 1)
EOF
fi

exit $fail
