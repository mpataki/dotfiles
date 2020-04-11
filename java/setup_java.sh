#!/bin/bash

function setup_java() {
  git_clone https://github.com/jenv/jenv.git ~/.jenv

  yaourt_sync intellij-idea-ce

  yaourt_sync jdk8-openjdk
  yaourt_sync jdk11-openjdk
  yaourt_sync maven

  check_and_link_file `pwd`/java/ideavimrc $HOME/.ideavimrc
}

print_with_color $YELLOW 'Setup Java Development Environment? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_java;;
  * ) print_with_color $GREEN 'skipping...';;
esac
