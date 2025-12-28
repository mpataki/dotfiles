#!/bin/bash
. lib/helpers.sh

function setup_claude() {
  check_and_link_file `pwd`/claude-config/agents/ $HOME/.claude
  check_and_link_file `pwd`/claude-config/skills/ $HOME/.claude
  check_and_link_file `pwd`/claude-config/commands/ $HOME/.claude
  check_and_link_file `pwd`/claude-config/CLAUDE.md $HOME/.claude/CLAUDE.md
  check_and_link_file `pwd`/claude-config/settings.json $HOME/.claude/settings.json

  if is_mac; then
    mkdir -p "$HOME/Library/Application Support/Claude"
    check_and_link_file `pwd`/claude-config/claude_desktop_config.json "$HOME/Library/Application Support/Claude/claude_desktop_config.json"
  fi
}

print_with_color $YELLOW 'Setup Claude? (y/n)'
read yn
case $yn in
  yes|Yes|YES|y|Y ) setup_claude;;
  * ) print_with_color $GREEN 'skipping...';;
esac
