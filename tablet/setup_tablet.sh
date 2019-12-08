#! /bin/bash

. lib/helpers.sh

function setup_tablet() {
  # stylus
  pacman_sync xf86-input-wacom

  # screen rotation
  pacman_sync iio-sensor-proxy-git
  pacman_sync screenrotator-git
}

print_with_color $YELLOW 'Setup tablet mode? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_tablet;;
  * ) print_with_color $GREEN 'skipping...';;
esac
