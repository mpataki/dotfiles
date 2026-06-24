#!/bin/bash

. lib/helpers.sh

function setup_go() {
    install_package go

    print_with_color $GREEN 'Installing Delve debugger...'
    go install github.com/go-delve/delve/cmd/dlv@latest

    print_with_color $GREEN 'Installing gofumpt formatter...'
    go install mvdan.cc/gofumpt@latest

    # Installed via package manager (not `go install`): golangci-lint's docs warn
    # that `go install` produces a binary with broken version info and disabled
    # features. Used by nvim-lint for Go files (see nvim/lua/mpataki/plugins/lint.lua).
    print_with_color $GREEN 'Installing golangci-lint...'
    install_package golangci-lint
}

print_with_color $YELLOW 'Setup Go Development Environment? (yes/no)'
read yn
case $yn in
    yes|Yes|YES|Y|y ) setup_go;;
    * ) print_with_color $GREEN 'skipping...';;
esac

