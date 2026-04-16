#!/bin/bash
. lib/helpers.sh

function setup_markdownlint() {
  check_and_link_file "$(pwd)/markdownlint/.markdownlintrc" "$HOME/.markdownlintrc"
}

print_with_color $YELLOW 'Setup markdownlint? (y/n)'
read yn
case $yn in
  yes|Yes|YES|y|Y ) setup_markdownlint;;
  * ) print_with_color $GREEN 'skipping...';;
esac
