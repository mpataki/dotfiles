#!/bin/bash

function setup_ruby() {
  yaourt_sync rbenv
  yaourt_sync ruby-build

  # 2.2.3... hopefully not needed for much longer
  curl -fsSL https://gist.github.com/mislav/055441129184a1512bb5.txt | PKG_CONFIG_PATH=/usr/lib/openssl-1.0/pkgconfig rbenv install --patch 2.2.3
}

print_with_color $YELLOW 'Setup Ruby? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_ruby;;
  * ) print_with_color $GREEN 'skipping...';;
esac
