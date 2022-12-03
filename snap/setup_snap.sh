#!/bin/bash

. lib/helpers.sh

function setup_snap() {
  yay_sync snapd
  systemctl enable snapd
  sudo ln -s /var/lib/snapd/snap /snap
  sudo snap install snap-store

  print_with_color $YELLOW 'Log out and back in or restart to finish the snap setup'
}

print_with_color $YELLOW 'Setup the Snap Store? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_snap;;
  * ) print_with_color $GREEN 'skipping...';;
esac
