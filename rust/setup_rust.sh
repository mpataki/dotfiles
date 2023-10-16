#!/bin/bash
. lib/helpers.sh

function setup_rust(){
  install_package rust
  install_package rust-analyzer
}

print_with_color $YELLOW 'Setup Rust? (y/n)'
read yn
case $yn in
  yes|Yes|YES|y|Y ) setup_rust;;
  * ) print_with_color $GREEN 'skipping...';;
esac

