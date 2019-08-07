#! /bin/bash

. lib/helpers.sh

function setup_xfce() {
  mkdir -p $HOME/.config/xfce4/xfconf/xfce-perchannel-xml

  check_and_link_file `pwd`/xfce/xfce4-keyboard-shortcuts.xml $HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml
}

print_with_color $YELLOW 'Setup xfce shortcuts? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_xfce;;
  * ) print_with_color $GREEN 'skipping...';;
esac

