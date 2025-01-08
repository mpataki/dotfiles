#!/bin/bash
. lib/helpers.sh

function setup_nvim(){
  install_package neovim
  install_package ripgrep
  install_package fd # telescope uses this to filesystem searching
  install_package luarocks # lua package manager
  
  mkdir -p $HOME/.config/nvim
  check_and_link_file `pwd`/nvim/init.lua $HOME/.config/nvim/init.lua
  check_and_link_file `pwd`/nvim/lua/ $HOME/.config/nvim
  check_and_link_file `pwd`/nvim/after/ $HOME/.config/nvim
  check_and_link_file `pwd`/nvim/ftplugin/ $HOME/.config/nvim

  # would be nice to get this workin via Mason
  install_package jdtls

  # for java features
  mkdir -p $HOME/.local/share/jars
  cp `pwd`/nvim/jars/* $HOME/.local/share/jars/
}

print_with_color $YELLOW 'Setup NeoVim? (y/n)'
read yn
case $yn in
  yes|Yes|YES|y|Y ) setup_nvim;;
  * ) print_with_color $GREEN 'skipping...';;
esac

