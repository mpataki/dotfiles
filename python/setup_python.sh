#!/bin/bash

function setup_python() {
  yaourt_sync pyenv
}

print_with_color $YELLOW 'Setup python? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_python;;
  * ) print_with_color $GREEN 'skipping...';;
esac
