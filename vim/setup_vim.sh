#!/bin/bash
. lib/helpers.sh

function setup_vim(){
  # GVIM -- TODO: remove once neovim is dialed in
  # install_package gvim
  # install_package the_silver_searcher

  # check_and_link_file `pwd`/vim/vimrc $HOME/.vimrc
  # check_and_link_file `pwd`/vim/colors $HOME/.vim/colors

  # if ! [ -e $HOME/.vim ]; then
    #mkdir $HOME/.vim
  #fi

  # Neovim
  install_package neovim
  install_package ripgrep
  
  mkdir -p $HOME/.config/nvim
  check_and_link_file `pwd`/vim/init.lua $HOME/.config/nvim/init.lua
  check_and_link_file `pwd`/vim/lua/ $HOME/.config/nvim
}

print_with_color $YELLOW 'Setup Vim? (y/n)'
read yn
case $yn in
  yes|Yes|YES|y|Y ) setup_vim;;
  * ) print_with_color $GREEN 'skipping...';;
esac

