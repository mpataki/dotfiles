#!/bin/bash

. lib/helpers.sh

function setup_k8s() {
  install_package stern

  mkdir -p "$HOME/.local/bin"
  check_and_link_file "$(pwd)/k8s/klogs" "$HOME/.local/bin/klogs"
}

print_with_color $YELLOW 'Setup k8s tools (stern, klogs)? (y/n)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_k8s;;
  * ) print_with_color $GREEN 'skipping...';;
esac
