#!/bin/bash

. lib/helpers.sh

function setup_node() {
    # nvm - node version manager
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
}

print_with_color $YELLOW 'Setup Node Development Environment? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_node;;
  * ) print_with_color $GREEN 'skipping...';;
esac
