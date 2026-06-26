#! /bin/bash

. lib/helpers.sh

function setup_duckdb() {
  install_package duckdb
}

print_with_color $YELLOW 'Setup duckdb? (y/n)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_duckdb;;
  * ) print_with_color $GREEN 'skipping...';;
esac
