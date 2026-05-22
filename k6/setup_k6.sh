#! /bin/bash

. lib/helpers.sh

function setup_k6() {
  install_package k6
}

print_with_color $YELLOW 'Setup k6? (y/n)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_k6;;
  * ) print_with_color $GREEN 'skipping...';;
esac
