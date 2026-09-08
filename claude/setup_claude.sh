#!/bin/bash
. lib/helpers.sh

function setup_claude() {
  check_and_link_file `pwd`/claude-config/agents/ $HOME/.claude
  check_and_link_file `pwd`/claude-config/skills/ $HOME/.claude
  check_and_link_file `pwd`/claude-config/commands/ $HOME/.claude
  check_and_link_file `pwd`/claude-config/CLAUDE.md $HOME/.claude/CLAUDE.md
  check_and_link_file `pwd`/claude-config/settings.json $HOME/.claude/settings.json
  check_and_link_file `pwd`/claude-config/workflows/ $HOME/.claude

  build_victoria_mcp
  sync_claude_mcp_servers
  sync_claude_marketplaces
  sync_claude_plugins
  sync_claude_work_profile
}

# Work profile: the `work` plugin (claude-config/plugins/work — Jira/acli, ER docs,
# team pulse, and the work MCP servers) is enabled only on a machine whose
# ~/.dotfiles-profile says `work`. Enablement lives in ~/.claude/settings.local.json
# (machine-local, not the dotfiles-tracked settings.json) so a personal Mac never
# loads it. Work-only permission allows come from settings.work.json the same way.
function sync_claude_work_profile() {
  command -v claude &> /dev/null || return
  local profile
  profile=$(cat "$HOME/.dotfiles-profile" 2>/dev/null)
  local local_settings="$HOME/.claude/settings.local.json"
  [ -f "$local_settings" ] || echo '{}' > "$local_settings"

  if [ "$profile" != "work" ]; then
    if jq -e '.enabledPlugins["work@mat-local"]' "$local_settings" >/dev/null 2>&1; then
      print_with_color $BLUE "profile is not work: disabling work plugin"
      jq 'del(.enabledPlugins["work@mat-local"])' "$local_settings" > "$local_settings.tmp" && mv "$local_settings.tmp" "$local_settings"
    fi
    return
  fi

  local marketplace="$(pwd)/claude-config/plugins"
  if ! claude plugin marketplace list 2>/dev/null | grep -q 'mat-local'; then
    print_with_color $BLUE "adding local marketplace: $marketplace"
    claude plugin marketplace add "$marketplace" 2>&1
  fi
  if ! claude plugin list 2>/dev/null | grep -q 'work@mat-local'; then
    print_with_color $BLUE "installing work plugin"
    claude plugin install work@mat-local 2>&1
    # install enables it in the shared settings.json; move that to the machine-local file
    local shared="$(pwd)/claude-config/settings.json"
    jq 'del(.enabledPlugins["work@mat-local"])' "$shared" > "$shared.tmp" && mv "$shared.tmp" "$shared"
  fi
  jq '.enabledPlugins["work@mat-local"] = true' "$local_settings" > "$local_settings.tmp" && mv "$local_settings.tmp" "$local_settings"

  local work_settings="$(pwd)/claude-config/settings.work.json"
  jq -s '.[0] as $l | .[1] as $w | $l | .permissions.allow = ((($l.permissions.allow // []) + ($w.permissions.allow // [])) | unique)' \
    "$local_settings" "$work_settings" > "$local_settings.tmp" && mv "$local_settings.tmp" "$local_settings"
  print_with_color $GREEN "work profile synced"
}

# Native VictoriaMetrics/VictoriaLogs MCP binaries; mcp-servers.json points at them.
function build_victoria_mcp() {
  if ! command -v go &> /dev/null; then
    print_with_color $YELLOW "go not found, skipping victoria MCP build"
    return
  fi
  bash "$(pwd)/claude/build_victoria_mcp.sh"
}

function sync_claude_mcp_servers() {
  if ! command -v claude &> /dev/null; then
    print_with_color $YELLOW "claude CLI not found, skipping MCP sync"
    return
  fi

  local mcp_config="$(pwd)/claude-config/mcp-servers.json"
  if [ ! -f "$mcp_config" ]; then
    print_with_color $YELLOW "mcp-servers.json not found, skipping MCP sync"
    return
  fi

  local existing
  existing=$(claude mcp list 2>/dev/null)

  jq -r 'to_entries[] | "\(.key)\t\(.value.type)"' "$mcp_config" | while IFS=$'\t' read -r name type; do
    if echo "$existing" | grep -q "$name"; then
      print_with_color $GREEN "MCP server already added: $name"
      continue
    fi

    if [ "$type" = "stdio" ]; then
      local command
      command=$(jq -r --arg n "$name" '.[$n].command' "$mcp_config")
      local args
      args=$(jq -r --arg n "$name" '.[$n].args // [] | join("\t")' "$mcp_config")
      local env_args=""
      env_args=$(jq -r --arg n "$name" '.[$n].env // {} | to_entries[] | "-e \(.key)=\(.value)"' "$mcp_config")

      print_with_color $BLUE "adding MCP server: $name (stdio: $command)"
      # name must precede -e: it is variadic and would swallow the name.
      eval claude mcp add "$name" --scope user $env_args -- "$command" $(echo "$args" | tr '\t' ' ') 2>&1
    else
      local url
      url=$(jq -r --arg n "$name" '.[$n].url' "$mcp_config")
      # Pass any headers (e.g. Authorization) through. Values may contain
      # ${VAR} references, which Claude Code expands at load time — keep them
      # literal here so the secret never lands in ~/.claude.json.
      local header_args=()
      while IFS= read -r header; do
        [ -n "$header" ] && header_args+=(--header "$header")
      done < <(jq -r --arg n "$name" '.[$n].headers // {} | to_entries[] | "\(.key): \(.value)"' "$mcp_config")
      print_with_color $BLUE "adding MCP server: $name ($url)"
      claude mcp add --transport "$type" "$name" "$url" "${header_args[@]}" --scope user 2>&1
    fi
  done
}

function sync_claude_marketplaces() {
  if ! command -v claude &> /dev/null; then
    return
  fi

  local settings="$(pwd)/claude-config/settings.json"
  if [ ! -f "$settings" ]; then
    return
  fi

  local existing
  existing=$(claude plugin marketplace list 2>/dev/null)

  jq -r '.extraKnownMarketplaces // {} | to_entries[] | "\(.key)\t\(.value.source.repo)"' "$settings" | while IFS=$'\t' read -r name repo; do
    if echo "$existing" | grep -q "$name"; then
      print_with_color $GREEN "marketplace already added: $name"
    else
      print_with_color $BLUE "adding marketplace: $name ($repo)"
      claude plugin marketplace add "$repo" 2>&1
    fi
  done
}

function sync_claude_plugins() {
  if ! command -v claude &> /dev/null; then
    print_with_color $YELLOW "claude CLI not found, skipping plugin sync"
    return
  fi

  local settings="$(pwd)/claude-config/settings.json"
  if [ ! -f "$settings" ]; then
    print_with_color $YELLOW "settings.json not found, skipping plugin sync"
    return
  fi

  local installed
  installed=$(claude plugin list 2>/dev/null)

  jq -r '.enabledPlugins // {} | keys[]' "$settings" | while read -r plugin; do
    if echo "$installed" | grep -q "$plugin"; then
      print_with_color $GREEN "plugin already installed: $plugin"
    else
      print_with_color $BLUE "installing plugin: $plugin"
      claude plugin install "$plugin" 2>&1
    fi
  done
}

print_with_color $YELLOW 'Setup Claude? (y/n)'
read yn
case $yn in
  yes|Yes|YES|y|Y ) setup_claude;;
  * ) print_with_color $GREEN 'skipping...';;
esac
