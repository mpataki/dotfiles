#!/bin/bash

function setup_slack() {
  yaourt_sync slack-desktop
}

print_with_color $YELLOW 'Setup Slack? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_slack;;
  * ) print_with_color $GREEN 'skipping...';;
esac
