#! /bin/bash

. lib/helpers.sh

function setup_yay() {
  pacman_sync yay
}

print_with_color $YELLOW 'Setup yay? (this is required for some packages) (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_yay;;
  * ) print_with_color $GREEN 'skipping...';;
esac


