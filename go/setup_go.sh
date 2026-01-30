#!/bin/bash

. lib/helpers.sh

function setup_go() {
    install_package go

    print_with_color $GREEN 'Installing Delve debugger...'
    go install github.com/go-delve/delve/cmd/dlv@latest
}

print_with_color $YELLOW 'Setup Go Development Environment? (yes/no)'
read yn
case $yn in
    yes|Yes|YES|Y|y ) setup_go;;
    * ) print_with_color $GREEN 'skipping...';;
esac

