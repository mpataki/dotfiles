#!/bin/bash
. lib/helpers.sh

function setup_git() {
  pacman_sync git
  pacman_sync github-cli
  pacman_sync diff-so-fancy

  check_and_link_file `pwd`/git/gitconfig $HOME/.gitconfig
  check_and_link_file `pwd`/git/gitignore $HOME/.gitignore
}

print_with_color $YELLOW 'Setup Git? (y/n)'
read yn
case $yn in
  yes|Yes|YES|y|Y ) setup_git;;
  * ) print_with_color $GREEN 'skipping...';;
esac

