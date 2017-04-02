#!/bin/bash

# TODO: link the rc.lua script

function setup_awesome() {
  pacman_sync awesome

  config_dir=$HOME/.config/awesome
  [ -e $config_dir || mkdir -p $config_dir
  check_and_link_file ./awesome/rc.lua $config_dir/rc.lua
}

print_with_color $YELLOW 'Setup AwesomeWM? (yes/no)'
read yn
case $yn in
  yes ) setup_awesome;;
  * ) print_with_color $GREEN 'skipping...';;
esac

