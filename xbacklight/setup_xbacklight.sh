#!/bin/bash

function setup_xbacklight() {
  pacman_sync xf86-video-intel
  pacman_sync xorg-xbacklight
  check_and_link_file `pwd`/xbacklight/xbacklight.conf /etc/X11/xorg.conf.d/xbacklight.conf true # use sudo
}

print_with_color $YELLOW 'Setup xbacklight? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_xbacklight;;
  * ) print_with_color $GREEN 'skipping...';;
esac
