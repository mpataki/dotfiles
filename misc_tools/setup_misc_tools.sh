#!/bin/bash

function setup_misc_tools() {
  pacman_sync htop
  pacman_sync openssh
  pacman_sync wget
  pacman_sync lsof
  pacman_sync jq
  pacman_sync ansible
  pacman_sync sshpass
  pacman_sync bind-tools
  yaourt_sync google-chrome
  pacman_sync netcat
  yaourt_sync boostnote
  yaourt_sync aws-cli
  yaourt_sync networkmanager-openvpn
  yaourt_sync network-manager-applet
  yaourt_sync ulauncher
  yaourt_sync net-tools
  yaourt_sync datagrip
  yaourt_sync packer
  yaourt_sync acroread

  gpg --recv-keys 1C61A2656FB57B7E4DE0F4C1FC918B335044912E
  yaourt_sync dropbox

  # dirty monaco font install
  mkdir -p $HOME/builds
  ch $HOMW/builds
  git clone git@github.com:cstrap/monaco-font.git
  cd monaco-font
  ./install-font-archlinux.sh http://jorrel.googlepages.com/Monaco_Linux.ttf
  cd .. && rm -rf monaco-font

  print_with_color $GREEN 'Setting the locale to en_US.UTF-8'
  localectl set-locale LANG=en_US.UTF-8
}

print_with_color $YELLOW 'Setup misc. tools? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_misc_tools;;
  * ) print_with_color $GREEN 'skipping...';;
esac
