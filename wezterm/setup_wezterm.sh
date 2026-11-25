#!/bin/bash
. lib/helpers.sh

function setup_wezterm(){
  if is_mac; then
    brew install --cask wezterm
  else
    install_package wezterm
  fi 

  check_and_link_file `pwd`/wezterm/wezterm.lua $HOME/.wezterm.lua

  # Daily check for a stable release that lets us drop the tmux margins
  # workaround (see wezterm/release-watch.sh). Remove once that's done.
  if is_mac; then
    local plist=com.mpataki.wezterm-release-watch.plist
    check_and_link_file `pwd`/wezterm/$plist $HOME/Library/LaunchAgents/$plist
    launchctl bootout gui/$(id -u)/${plist%.plist} 2>/dev/null || true
    launchctl bootstrap gui/$(id -u) $HOME/Library/LaunchAgents/$plist
  fi
}

print_with_color $YELLOW 'Setup Wezterm? (y/n)'
read yn
case $yn in
  yes|Yes|YES|y|Y ) setup_wezterm;;
  * ) print_with_color $GREEN 'skipping...';;
esac

