#!/bin/bash
. lib/helpers.sh

function setup_vim(){
  install_package neovim
  install_package ripgrep
  install_package fd # telescope uses this to filesystem searching
  
  mkdir -p $HOME/.config/nvim
  check_and_link_file `pwd`/vim/init.lua $HOME/.config/nvim/init.lua
  check_and_link_file `pwd`/vim/lua/ $HOME/.config/nvim
  check_and_link_file `pwd`/vim/after/ $HOME/.config/nvim
  check_and_link_file `pwd`/vim/ftplugin/ $HOME/.config/nvim

  # language servers
  #   note: most most of these to mason
  install_package lua-language-server
  install_package eslint
  install_package bash-language-server
  install_package yaml-language-server
  install_package jdtls

  # for java features
  mkdir -p $HOME/.local/share/jars
  cp `pwd`/vim/jars/* $HOME/.local/share/jars/
}

print_with_color $YELLOW 'Setup Vim? (y/n)'
read yn
case $yn in
  yes|Yes|YES|y|Y ) setup_vim;;
  * ) print_with_color $GREEN 'skipping...';;
esac

