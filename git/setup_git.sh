#!/bin/bash
. lib/helpers.sh

function setup_git() {
  install_package git

  if is_mac; then
    install_package gh
  else
    install_package github-cli
  fi

  install_package git-delta
  install_package git-lfs

  check_and_link_file `pwd`/git/gitconfig $HOME/.gitconfig
  check_and_link_file `pwd`/git/gitignore $HOME/.gitignore
  check_and_link_file `pwd`/git/gitconfig.1password $HOME/.gitconfig.1password
}

print_with_color $YELLOW 'Setup Git? (y/n)'
read yn
case $yn in
  yes|Yes|YES|y|Y ) setup_git;;
  * ) print_with_color $GREEN 'skipping...';;
esac

