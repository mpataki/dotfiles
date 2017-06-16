#! /bin/bash

. lib/helpers.sh

function setup_xkb() {
  check_and_link_file `pwd`/xkb/Xkeymap $HOME/.XKeymap

  pacman_sync xorg-xkbcomp
  pacman_sync xorg-xev
}

print_with_color $YELLOW 'Setup XKB? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_xkb;;
  * ) print_with_color $GREEN 'skipping...';;
esac
