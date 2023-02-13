#!/bin/bash

function setup_dotnet() {
  yay_sync dotnet-sdk

  sudo sh dotnet/dotnet-install.sh --install-dir /usr/share/dotnet -version 5.0.405
}

print_with_color $YELLOW 'Setup Dotnet Development Environment? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_dotnet;;
  * ) print_with_color $GREEN 'skipping...';;
esac
