#!/bin/bash

function setup_intel_graphics() {
  pacman_sync xf86-video-intel
  check_and_link_file `pwd`/intel_graphics/20-intel.conf /etc/X11/xorg.conf.d/20-intel.conf true # use sudo
}

print_with_color $YELLOW 'Setup intel graphics? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_intel_graphics;;
  * ) print_with_color $GREEN 'skipping...';;
esac
