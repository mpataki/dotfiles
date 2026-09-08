#!/bin/bash
# Codex-native setup. Installs the same claude-config sources Claude Code uses:
#   - global instructions: ~/.codex/AGENTS.md -> claude-config/codex/AGENTS.md
#     (rendered from CLAUDE.md by claude-config/codex/render-agents-md.py)
#   - hooks: ~/.codex/hooks.json -> claude-config/codex/hooks.json (same scripts
#     as Claude; Codex asks once to trust them via /hooks)
#   - skills: one owned symlink per skill in ~/.agents/skills/<name>
#   - agent roles: ~/.codex/agents/<name>.toml rendered from claude-config/agents/*.md
#   - MCP servers from mcp-servers.json via `codex mcp add`
#   - plugins from settings.json enabledPlugins via `codex plugin`
#   - work profile (~/.dotfiles-profile == work): the local `work` plugin
#
# Codex owns ~/.codex/config.toml. MCPs and plugins go through the codex CLI,
# which merges into it; the one direct edit (signing env keys) only ever adds
# missing keys and verifies the file still parses. Unmanaged skills (real
# directories we did not create) are reported, never replaced.
. lib/helpers.sh

CONFIG="$(pwd)/claude-config"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
AGENT_SKILLS="$HOME/.agents/skills"

function setup_codex() {
  if ! command -v codex &> /dev/null; then
    print_with_color $YELLOW "codex CLI not found, skipping Codex setup"
    return
  fi
  mkdir -p "$CODEX_HOME" "$AGENT_SKILLS" "$CODEX_HOME/agents"

  render_codex_sources
  link_owned "$CONFIG/codex/AGENTS.md" "$CODEX_HOME/AGENTS.md"
  link_owned "$CONFIG/codex/hooks.json" "$CODEX_HOME/hooks.json"
  sync_codex_skills
  sync_codex_agents
  sync_codex_mcp_servers
  sync_codex_plugins
  sync_codex_work_profile
  sync_codex_signing_env
}

# Same GIT_CONFIG_* overrides Claude gets from settings.json env: commits made
# by Codex sign with the machine's Secure Enclave key instead of prompting
# 1Password. The only direct config.toml edit we make, and it only adds keys.
function sync_codex_signing_env() {
  python3 "$CONFIG/codex/set-env-policy.py" "$CODEX_HOME/config.toml" \
    GIT_CONFIG_COUNT=2 \
    GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false \
    GIT_CONFIG_KEY_1=include.path "GIT_CONFIG_VALUE_1=$HOME/.gitconfig-agent-signing"
}

# Render AGENTS.md and agent role TOMLs from the Claude-native sources. The
# rendered files are tracked in claude-config so the diff is reviewable.
function render_codex_sources() {
  python3 "$CONFIG/codex/render-agents-md.py" "$CONFIG/CLAUDE.md" "$CONFIG/codex/AGENTS.md" \
    && print_with_color $GREEN "rendered codex/AGENTS.md from CLAUDE.md"
  python3 "$CONFIG/codex/render-agent-roles.py" "$CONFIG/agents" "$CONFIG/codex/agents" \
    && print_with_color $GREEN "rendered codex/agents/*.toml from agents/*.md"
}

# Create an owned symlink; leave a correct one alone; report anything else.
# Never deletes a real file or directory — that is the user's call.
function link_owned() {
  local src=$1 dst=$2
  if [ -L "$dst" ]; then
    if [ "$(readlink "$dst")" = "$src" ]; then
      return
    fi
    print_with_color $BLUE "relinking $dst -> $src"
    ln -sfn "$src" "$dst"
    return
  fi
  if [ -e "$dst" ]; then
    print_with_color $YELLOW "unmanaged: $dst exists and is not a link (wanted -> $src); leaving it"
    return 1
  fi
  ln -s "$src" "$dst"
  print_with_color $GREEN "linked $dst -> $src"
}

# One link per skill so local, unmanaged skills can coexist in the same dir.
# Links that point into claude-config but whose source is gone are removed
# (the skill was retired); real directories are only reported.
function sync_codex_skills() {
  local d name
  for d in "$CONFIG"/skills/*/; do
    name=$(basename "$d")
    link_owned "${d%/}" "$AGENT_SKILLS/$name"
  done
  for d in "$AGENT_SKILLS"/*/; do
    [ -L "${d%/}" ] || continue
    case "$(readlink "${d%/}")" in
      "$CONFIG"/skills/*) [ -e "${d%/}" ] || { print_with_color $BLUE "removing retired skill link $(basename "$d")"; rm "${d%/}"; } ;;
    esac
  done
}

function sync_codex_agents() {
  local f name
  for f in "$CONFIG"/codex/agents/*.toml; do
    [ -e "$f" ] || continue
    name=$(basename "$f")
    link_owned "$f" "$CODEX_HOME/agents/$name"
  done
}

# Same source as Claude (mcp-servers.json). `codex` itself is skipped — Codex
# does not delegate to Codex. Headers become --bearer-token-env-var when they
# are a single Bearer ${VAR} reference; anything else is reported.
function sync_codex_mcp_servers() {
  local existing
  existing=$(codex mcp list 2>/dev/null)
  jq -r 'to_entries[] | select(.key != "codex") | .key' "$CONFIG/mcp-servers.json" | while read -r name; do
    if echo "$existing" | grep -qw "$name"; then
      print_with_color $GREEN "codex MCP already added: $name"
      continue
    fi
    local type; type=$(jq -r --arg n "$name" '.[$n].type' "$CONFIG/mcp-servers.json")
    if [ "$type" = "stdio" ]; then
      local cmd; cmd=$(jq -r --arg n "$name" '.[$n].command' "$CONFIG/mcp-servers.json")
      local args; args=$(jq -r --arg n "$name" '.[$n].args // [] | join("\t")' "$CONFIG/mcp-servers.json")
      local env_args=()
      while IFS= read -r kv; do [ -n "$kv" ] && env_args+=(--env "$kv"); done \
        < <(jq -r --arg n "$name" '.[$n].env // {} | to_entries[] | "\(.key)=\(.value)"' "$CONFIG/mcp-servers.json")
      print_with_color $BLUE "adding codex MCP server: $name (stdio: $cmd)"
      # shellcheck disable=SC2086
      codex mcp add "$name" "${env_args[@]}" -- "$cmd" $(echo "$args" | tr '\t' ' ') 2>&1
    else
      local url; url=$(jq -r --arg n "$name" '.[$n].url' "$CONFIG/mcp-servers.json")
      local auth; auth=$(jq -r --arg n "$name" '.[$n].headers.Authorization // ""' "$CONFIG/mcp-servers.json")
      local token_args=()
      if [[ "$auth" =~ ^Bearer\ \$\{([A-Za-z_][A-Za-z0-9_]*)(:-)?\}$ ]]; then
        token_args=(--bearer-token-env-var "${BASH_REMATCH[1]}")
      elif [ -n "$auth" ]; then
        print_with_color $YELLOW "codex MCP $name: header shape not supported by codex mcp add; add it by hand"
        continue
      fi
      print_with_color $BLUE "adding codex MCP server: $name ($url)"
      codex mcp add "$name" --url "$url" "${token_args[@]}" 2>&1
    fi
  done
}

# Codex reads Claude-format marketplaces, so enabledPlugins carries over.
# LSP plugins are Claude-only (Codex has no LSP tool) and are skipped.
function sync_codex_plugins() {
  local installed
  installed=$(codex plugin list 2>/dev/null)
  jq -r '.enabledPlugins // {} | keys[]' "$CONFIG/settings.json" | while read -r plugin; do
    case "$plugin" in *@claude-code-lsps|*-lsp@*) continue ;; esac
    if echo "$installed" | grep -q "$plugin"; then
      print_with_color $GREEN "codex plugin already installed: $plugin"
    else
      print_with_color $BLUE "installing codex plugin: $plugin"
      codex plugin add "$plugin" 2>&1
    fi
  done
}

function sync_codex_work_profile() {
  local profile; profile=$(cat "$HOME/.dotfiles-profile" 2>/dev/null)
  if [ "$profile" != "work" ]; then
    if codex plugin list 2>/dev/null | grep -q 'work@mat-local'; then
      print_with_color $BLUE "profile is not work: removing codex work plugin"
      codex plugin remove work@mat-local 2>&1
    fi
    return
  fi
  if ! codex plugin marketplace list 2>/dev/null | grep -q 'mat-local'; then
    print_with_color $BLUE "adding local marketplace to codex"
    codex plugin marketplace add "$CONFIG/plugins" 2>&1
  fi
  if ! codex plugin list 2>/dev/null | grep -q 'work@mat-local'; then
    print_with_color $BLUE "installing codex work plugin"
    codex plugin add work@mat-local 2>&1
  fi
}

print_with_color $YELLOW 'Setup Codex? (y/n)'
read yn
case $yn in
  yes|Yes|YES|y|Y ) setup_codex;;
  * ) print_with_color $GREEN 'skipping...';;
esac
