
#!/bin/bash
. lib/helpers.sh

function setup_opencode() {
    install_package anomalyco/tap/opencode  opencode
}

print_with_color $YELLOW 'Setup opencode? (y/n)'
read yn
case $yn in
  yes|Yes|YES|y|Y ) setup_opencode;;
  * ) print_with_color $GREEN 'skipping...';;
esac
