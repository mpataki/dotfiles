#! /bin/bash

function setup_xterm() {
  check_and_link_file `pwd`/xterm/Xresources $HOME/.Xresources

  pacman_sync xterm
  pacman_sync xorg-xrdb
}

print_with_color $YELLOW 'Setup XTerm? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_xterm;;
  * ) print_with_color $GREEN 'skipping...';;
esac
