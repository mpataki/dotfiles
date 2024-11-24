#!/bin/bash

. lib/helpers.sh

function setup_aerospace() {
    if is_mac; then
        brew install --cask nikitabobko/tap/aerospace

        check_and_link_file `pwd`/aerospace/aerospace.toml $HOME/.aerospace.toml
    fi
}

print_with_color $YELLOW 'Setup Aerospace? (y/n)'
read yn
case $yn in
    yes|Yes|YES|y|Y ) setup_aerospace;;
    * ) print_with_color $GREEN 'skipping...';;
esac

