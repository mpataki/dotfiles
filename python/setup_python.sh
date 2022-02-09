#!/bin/bash

function setup_python() {
  yay_sync pyenv
  yay_sync pyenv-virtualenv
}

print_with_color $YELLOW 'Setup python? (y/n)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_python;;
  * ) print_with_color $GREEN 'skipping...';;
esac
