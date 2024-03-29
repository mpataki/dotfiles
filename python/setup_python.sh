#!/bin/bash
. lib/helpers.sh

function setup_python() {
  install_package pyenv
  install_package pyenv-virtualenv
}

print_with_color $YELLOW 'Setup python? (y/n)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_python;;
  * ) print_with_color $GREEN 'skipping...';;
esac
