#!/bin/bash
. lib/helpers.sh

function setup_ssh() {
  # ControlPath in ssh/config points here; ssh won't create it itself.
  mkdir -p $HOME/.ssh/sockets
  chmod 700 $HOME/.ssh/sockets
  check_and_link_file `pwd`/ssh/config $HOME/.ssh/config
  check_and_link_file `pwd`/ssh/allowed_signers $HOME/.ssh/allowed_signers
}

print_with_color $YELLOW 'Setup SSH? (y/n)'
read yn
case $yn in
  yes|Yes|YES|y|Y ) setup_ssh;;
  * ) print_with_color $GREEN 'skipping...';;
esac

