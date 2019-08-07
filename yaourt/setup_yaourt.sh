#! /bin/bash

. lib/helpers.sh

function setup_yaourt() {
  if ! [[ `which yaourt` ]]; then
    here=`pwd`
    sudo pacman -S --needed base-devel git wget yajl
    cd /tmp
    git clone https://aur.archlinux.org/package-query.git
    cd package-query/
    makepkg -si && cd /tmp/
    git clone https://aur.archlinux.org/yaourt.git
    cd yaourt/
    makepkg -si
    cd $here
  fi
}

print_with_color $YELLOW 'Setup yaourt? (this is required for some packages) (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_yaourt;;
  * ) print_with_color $GREEN 'skipping...';;
esac


