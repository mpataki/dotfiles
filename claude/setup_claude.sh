#!/bin/bash
. lib/helpers.sh

function setup_claude() {
  check_and_link_file `pwd`/claude-config/agents/ $HOME/.claude/agents
  check_and_link_file `pwd`/claude-config/skills/ $HOME/.claude/skills
  check_and_link_file `pwd`/claude-config/CLAUDE.md $HOME/.claude/CLAUDE.md
  check_and_link_file `pwd`/claude-config/settings.json $HOME/.claude/settings.json
}

print_with_color $YELLOW 'Setup Claude? (y/n)'
read yn
case $yn in
  yes|Yes|YES|y|Y ) setup_claude;;
  * ) print_with_color $GREEN 'skipping...';;
esac
