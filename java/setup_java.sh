#!/bin/bash

function setup_java() {
  pacman_sync jdk8-openjdk
  aur_install intellij-idea-ultimate-edition 'https://aur.archlinux.org/intellij-idea-ultimate-edition.git'
}

print_with_color $YELLOW 'Setup Java Development Environment? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_java;;
  * ) print_with_color $GREEN 'skipping...';;
esac
