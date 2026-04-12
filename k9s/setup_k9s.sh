#! /bin/bash

. lib/helpers.sh

function setup_k9s() {
  install_package k9s

  local config_dir="$HOME/Library/Application Support/k9s"

  if ! is_mac; then
    config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/k9s"
  fi

  mkdir -p "$config_dir"
  check_and_link_file "$(pwd)/k9s/config.yaml" "$config_dir/config.yaml"
  check_and_link_file "$(pwd)/k9s/plugins.yaml" "$config_dir/plugins.yaml"
}

print_with_color $YELLOW 'Setup k9s? (y/n)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_k9s;;
  * ) print_with_color $GREEN 'skipping...';;
esac
