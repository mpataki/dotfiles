#!/bin/bash

. lib/helpers.sh

function setup_java() {
  if is_mac; then
    install_package jenv
    # brew install openjdk@8 # requires x86. no good on arm
    brew install openjdk@11
    brew install openjdk@17
    brew install openjdk@19

    jenv add /opt/homebrew/Cellar/openjdk@11/*/
    jenv add /opt/homebrew/Cellar/openjdk@17/*/
    jenv add /opt/homebrew/Cellar/openjdk/*/

  else
    git_clone https://github.com/jenv/jenv.git ~/.jenv

    install_package jdk8-openjdk
    install_package jdk11-openjdk
    install_package jdk17-openjdk
    install_package jdk-openjdk
  fi

  mkdir -p $HOME/.jenv/versions

  install_package maven
  install_package gradle

  check_and_link_file `pwd`/java/ideavimrc $HOME/.ideavimrc
}

print_with_color $YELLOW 'Setup Java Development Environment? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_java;;
  * ) print_with_color $GREEN 'skipping...';;
esac
