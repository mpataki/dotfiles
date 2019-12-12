#! /bin/bash

. lib/helpers.sh

function setup_virtual_keyboard() {
  yaourt_sync onboard
  systemctl enable acpid
  systemctl start acpid

  print_with_color $YELLOW 'You may want to explore the onboard keyboard settings'
}

print_with_color $YELLOW 'Setup virtual keyboard? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_virtual_keyboard;;
  * ) print_with_color $GREEN 'skipping...';;
esac
