#!/bin/bash
. lib/helpers.sh

function setup_misc_tools() {
  pacman_sync cmake
  pacman_sync make
  pacman_sync htop
  pacman_sync openssh
  pacman_sync wget
  pacman_sync lsof
  pacman_sync jq
  pacman_sync ansible
  pacman_sync sshpass
  pacman_sync bind-tools
  # yay_sync google-chrome
  pacman_sync netcat
  # yay_sync boostnote
  yay_sync aws-cli
  # yay_sync networkmanager-openvpn
  # yay_sync network-manager-applet
  # yay_sync net-tools
  yay_sync intellij-idea-ultimate-edition
  yay_sync datagrip
  yay_sync pycharm-professional
  yay_sync webstorm
  yay_sync packer
  yay_sync tcpflow
  yay_sync yubikey-manager-qt
  yay_sync albert-bin
  yay_sync brave-bin
  yay_sync slack-desktop
  yay_sync ksnip
  yay_sync k9s
  yay_sync net-tools
  yay_sync grpcurl

  gpg --recv-keys 1C61A2656FB57B7E4DE0F4C1FC918B335044912E
  yay_sync dropbox

  yay_sync libserdes-git
  yay_sync yajl

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
