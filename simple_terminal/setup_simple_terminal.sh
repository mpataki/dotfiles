#! /bin/bash

. lib/helpers.sh

function setup_st() {
  yay_sync pkgconfig
  git_clone https://git.suckless.org/st $HOME/builds/st

  here=`pwd`
  cp $here/simple_terminal/config.h $HOME/builds/st/config.h
  cp $here/simple_terminal/config.mk $HOME/builds/st/config.mk
  cd $HOME/builds/st

  sudo make clean install

  cd $here
  rm -rf $HOME/builds/st
}

print_with_color $YELLOW 'Setup simple terminal (st)? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_st;;
  * ) print_with_color $GREEN 'skipping...';;
esac
