#!/bin/bash
. lib/helpers.sh

function setup_gws() {
  print_with_color $BLUE "Installing Google Workspace CLI (gws) and Google Cloud SDK (gcloud)"

  if is_mac; then
    install_package googleworkspace-cli gws
    install_package gcloud-cli gcloud
  else
    print_with_color $YELLOW "gws: manual install required on Linux — see https://github.com/googleworkspace/cli"
    return
  fi

  print_with_color $GREEN "gws and gcloud installed."
  print_with_color $YELLOW "One-time auth setup:"
  print_with_color $YELLOW "  1. gws auth setup          # creates GCP project + OAuth credentials"
  print_with_color $YELLOW "  2. gws auth login --scopes calendar"
  print_with_color $YELLOW "  3. gws calendar +agenda --today   # verify it works"
}

print_with_color $YELLOW 'Setup Google Workspace CLI (gws)? (y/n)'
read yn
case $yn in
  yes|Yes|YES|y|Y ) setup_gws;;
  * ) print_with_color $GREEN 'skipping...';;
esac
