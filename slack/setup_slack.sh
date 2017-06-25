#!/bin/bash

function setup_slack() {
  aur_install slack_desktop 'https://aur.archlinux.org/slack-desktop.git'
}

print_with_color $YELLOW 'Setup Slack? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_slack;;
  * ) print_with_color $GREEN 'skipping...';;
esac
