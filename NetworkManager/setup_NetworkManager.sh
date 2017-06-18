#!/bin/bash

function setup_NetworkManager() {
  pacman_sync NetworkManger
  systemctl start NetworkManager
  systemctl enable NetworkManager
}


print_with_color $YELLOW 'Setup NetworkManager? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_NetworkManager;;
  * ) print_with_color $GREEN 'skipping...';;
esac
