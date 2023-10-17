#!/bin/bash
. lib/helpers.sh

function setup_rust(){
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
}

print_with_color $YELLOW 'Setup Rust? (y/n)'
read yn
case $yn in
  yes|Yes|YES|y|Y ) setup_rust;;
  * ) print_with_color $GREEN 'skipping...';;
esac

