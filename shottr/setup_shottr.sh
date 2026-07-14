#!/bin/bash
. lib/helpers.sh

# Shottr: fast native macOS screenshot tool (region/window/screen hotkeys,
# clipboard-first capture, arrows/blur/OCR/scrolling). mac-only.
function setup_shottr() {
  if is_mac; then
    brew install --cask shottr
  fi
}

print_with_color $YELLOW 'Setup Shottr? (y/n)'
read yn
case $yn in
  yes|Yes|YES|y|Y ) setup_shottr;;
  * ) print_with_color $GREEN 'skipping...';;
esac
