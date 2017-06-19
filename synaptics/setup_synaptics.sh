#!/bin/bash

function setup_input_synaptics() {
  pacman_sync xf86-input-synaptics
  check_and_link_file `pwd`/synaptics/70-synaptics.conf /etc/X11/xorg.conf.d/70-synaptics.conf true # use sudo
}

print_with_color $YELLOW 'Setup xf86-input-synaptics (trackpad)? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_input_synaptics;;
  * ) print_with_color $GREEN 'skipping...';;
esac
