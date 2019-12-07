#! /bin/bash

. lib/helpers.sh

function setup_wacom() {
  pacman_sync xf86-input-wacom
}

print_with_color $YELLOW 'Setup wacom? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_wacom;;
  * ) print_with_color $GREEN 'skipping...';;
esac
