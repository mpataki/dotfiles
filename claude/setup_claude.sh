#!/bin/bash
. lib/helpers.sh

function setup_claude() {
  check_and_link_file `pwd`/claude-config/agents/ $HOME/.claude
  check_and_link_file `pwd`/claude-config/skills/ $HOME/.claude
  check_and_link_file `pwd`/claude-config/commands/ $HOME/.claude
  check_and_link_file `pwd`/claude-config/CLAUDE.md $HOME/.claude/CLAUDE.md
  check_and_link_file `pwd`/claude-config/settings.json $HOME/.claude/settings.json

  sync_claude_mcp_servers
  sync_claude_marketplaces
  sync_claude_plugins
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
      eval claude mcp add $env_args "$name" --scope user -- "$command" $(echo "$args" | tr '\t' ' ') 2>&1
    else
      local url
      url=$(jq -r --arg n "$name" '.[$n].url' "$mcp_config")
      print_with_color $BLUE "adding MCP server: $name ($url)"
      claude mcp add --transport "$type" "$name" "$url" --scope user 2>&1
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
