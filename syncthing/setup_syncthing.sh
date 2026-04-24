#!/bin/bash
. lib/helpers.sh

function setup_syncthing() {
  if is_mac; then
    install_package syncthing

    print_with_color $YELLOW "Start syncthing as a background service now? (y/n)"
    read yn
    case $yn in
      yes|Yes|YES|y|Y )
        brew services start syncthing
        print_with_color $GREEN "Syncthing running. Web UI: http://localhost:8384"
        ;;
      * ) print_with_color $GREEN 'skipping service start...';;
    esac
  else
    yay_sync syncthing

    print_with_color $YELLOW "Enable syncthing user service now? (y/n)"
    read yn
    case $yn in
      yes|Yes|YES|y|Y )
        systemctl --user enable --now syncthing.service
        print_with_color $GREEN "Syncthing running. Web UI: http://localhost:8384"
        ;;
      * ) print_with_color $GREEN 'skipping service start...';;
    esac
  fi

  print_with_color $GREEN "Next steps:"
  print_with_color $GREEN "  1. Install Syncthing on Android (F-Droid: Syncthing or Syncthing-Fork)"
  print_with_color $GREEN "  2. Open http://localhost:8384 and pair your phone (Actions > Show ID, scan on phone)"
  print_with_color $GREEN "  3. Share the vault folder (~/obsidian-notes-vault) with the phone"
  print_with_color $GREEN "  4. Vault already contains .stignore — Syncthing will honour it automatically"
}

print_with_color $YELLOW 'Setup Syncthing? (y/n)'
read yn
case $yn in
  yes|Yes|YES|y|Y ) setup_syncthing;;
  * ) print_with_color $GREEN 'skipping...';;
esac
