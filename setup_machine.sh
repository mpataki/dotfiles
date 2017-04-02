#!/usr/bin/env bash

. lib/helpers.sh

print_with_color $GREEN "This script installs programs. Please enter your root password."
[ `whoami` = root ] || exec su -c $0 root

. bash/setup_bash.sh
. git/setup_git.sh
. vim/setup_vim.sh
. gnupg/setup_gnupg.sh

# TODO: install rbenv
# TODO: install wget
# TODO: install pass
# TODO: install chrome
# TODO: install Albert (?)
# TODO: install awesome

. $HOME/.bash_profile

