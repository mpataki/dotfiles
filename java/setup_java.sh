#!/bin/bash

function setup_java() {
  pacman_sync jdk8-openjdk
  pacman_sync jre8-openjdk
}

print_with_color $YELLOW 'Setup Java? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_java;;
  * ) print_with_color $GREEN 'skipping...';;
esac
