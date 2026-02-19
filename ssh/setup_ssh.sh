#!/bin/bash
. lib/helpers.sh

function setup_ssh() {
  check_and_link_file `pwd`/ssh/config $HOME/.ssh/config
}

print_with_color $YELLOW 'Setup SSH? (y/n)'
read yn
case $yn in
  yes|Yes|YES|y|Y ) setup_ssh;;
  * ) print_with_color $GREEN 'skipping...';;
esac

