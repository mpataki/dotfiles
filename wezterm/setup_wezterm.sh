#!/bin/bash
. lib/helpers.sh

function setup_wezterm(){
  if is_mac; then
    brew install --cask wezterm
  else
    install_package wezterm
  fi 

  check_and_link_file `pwd`/wezterm/wezterm.lua $HOME/.wezterm.lua
}

print_with_color $YELLOW 'Setup Wezterm? (y/n)'
read yn
case $yn in
  yes|Yes|YES|y|Y ) setup_wezterm;;
  * ) print_with_color $GREEN 'skipping...';;
esac

