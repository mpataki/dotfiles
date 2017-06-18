#! /bin/bash

function setup_x() {
  pacman_sync xorg-xinit
  pacman_sync xf86-video # this might be a bit too system specific...
  pacman_sync xclip
  check_and_link_file `pwd`/x/xinitrc $HOME/.xinitrc
}

print_with_color $YELLOW 'Setup X? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_x;;
  * ) print_with_color $GREEN 'skipping...';;
esac
