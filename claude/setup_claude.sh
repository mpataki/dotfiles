#!/bin/bash
. lib/helpers.sh

function setup_claude() {
  check_and_link_file `pwd`/agent-config/agents/ $HOME/.claude
  check_and_link_file `pwd`/agent-config/skills/ $HOME/.claude
  check_and_link_file `pwd`/agent-config/commands/ $HOME/.claude
  check_and_link_file `pwd`/agent-config/CLAUDE.md $HOME/.claude/CLAUDE.md
  check_and_link_file `pwd`/agent-config/workflows/ $HOME/.claude

  render_claude_settings || return 1
  sync_claude_mcp_servers
  sync_claude_marketplaces
  sync_claude_plugins
  sync_claude_work_profile
}

# ~/.claude/settings.json is RENDERED, not linked: it is the only user-scope file
# Claude Code reads (there is no ~/.claude/settings.local.json), so the work
# profile has to be baked into it. agent/render_claude_settings.sh merges
# settings.work.json on top of settings.json when ~/.dotfiles-profile says `work`.
# Claude Code also writes to this file (/config, plugin enable, "always allow"),
# so it can drift from the sources; we never clobber drift — reconcile first.
function render_claude_settings() {
  local dst="$HOME/.claude/settings.json"
  local render="$(pwd)/agent/render_claude_settings.sh"
  if [ -L "$dst" ]; then
    print_with_color $BLUE "settings.json was a link into the repo; replacing with a rendered file"
    rm -f "$dst"
  fi
  if [ -f "$dst" ] && ! cmp -s <("$render" | jq -S .) <(jq -S . "$dst"); then
    print_with_color $RED "settings.json has drifted from agent-config; not overwriting."
    print_with_color $RED "run agent/reconcile_claude_settings.sh (--apply to port the drift back), then re-run."
    return 1
  fi
  "$render" > "$dst.tmp" && mv "$dst.tmp" "$dst"
  print_with_color $GREEN "rendered $dst (profile: $(cat "$HOME/.dotfiles-profile" 2>/dev/null || echo personal))"
  # written by the pre-rendering setup; Claude Code never read it
  [ -e "$HOME/.claude/settings.local.json" ] && rm -f "$HOME/.claude/settings.local.json" \
    && print_with_color $BLUE "removed ~/.claude/settings.local.json (dead: Claude Code has no user-level local file)"
  return 0
}

# Work profile: the `work` plugin (agent-config/plugins/work — Jira/acli, ER docs,
# team pulse, and the work MCP servers) exists only on a machine whose
# ~/.dotfiles-profile says `work`. Its enablement, marketplace and permission
# allows are declared in settings.work.json and land via render_claude_settings;
# this only makes sure the plugin itself is installed.
function sync_claude_work_profile() {
  command -v claude &> /dev/null || return
  [ "$(cat "$HOME/.dotfiles-profile" 2>/dev/null)" = work ] || return 0

  local marketplace="$(pwd)/agent-config/plugins"
  if ! claude plugin marketplace list 2>/dev/null | grep -q 'mat-local'; then
    print_with_color $BLUE "adding local marketplace: $marketplace"
    claude plugin marketplace add "$marketplace" 2>&1
  fi
  if ! claude plugin list 2>/dev/null | grep -q 'work@mat-local'; then
    print_with_color $BLUE "installing work plugin"
    claude plugin install work@mat-local 2>&1
  fi
  print_with_color $GREEN "work profile synced"
}

function sync_claude_mcp_servers() {
  if ! command -v claude &> /dev/null; then
    print_with_color $YELLOW "claude CLI not found, skipping MCP sync"
    return
  fi

  local mcp_config="$(pwd)/agent-config/mcp-servers.json"
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

  local settings="$(pwd)/agent-config/settings.json"
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

  local settings="$(pwd)/agent-config/settings.json"
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
