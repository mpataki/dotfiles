#!/bin/bash

function setup_ruby() {
  yaourt_sync rbenv
  yaourt_sync ruby-build
}

print_with_color $YELLOW 'Setup Ruby? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_ruby;;
  * ) print_with_color $GREEN 'skipping...';;
esac
