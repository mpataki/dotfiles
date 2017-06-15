#! /bin/bash

function setup_x() {
  # TODO: install packages

  check_and_link_file `pwd`/x/xinitrc $HOME/.xintrc
}

print_with_color $YELLOW 'Setup X? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_x;;
  * ) print_with_color $GREEN 'skipping...';;
esac
