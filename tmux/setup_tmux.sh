#! /bin/bash

. lib/helpers.sh

function setup_tmux() {
  pacman_sync tmux
  pacman_sync xsel

  git_clone https://github.com/tmux-plugins/tpm $HOME/.tmux/plugins/tpm

  check_and_link_file `pwd`/tmux/tmux.conf $HOME/.tmux.conf

  print_with_color $YELLOW 'remember to install the plugins if this is the first run (prefix + I)'
}

print_with_color $YELLOW 'Setup tmux? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_tmux;;
  * ) print_with_color $GREEN 'skipping...';;
esac
