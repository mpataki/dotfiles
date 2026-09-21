#!/bin/bash
. lib/helpers.sh

VAULT="$HOME/obsidian-notes-vault"
FOLDER_ID='obsidian-vault'

# LAN-only posture: no global discovery, no public relays, no NAT punching.
# Devices find each other by local broadcast, so syncing only happens on a
# shared network. Every node must apply this or it will still reach out.
function configure_syncthing() {
  print_with_color $GREEN 'Waiting for the Syncthing daemon...'
  for _ in $(seq 1 30); do
    syncthing cli show system >/dev/null 2>&1 && break
    sleep 1
  done

  if ! syncthing cli show system >/dev/null 2>&1; then
    print_with_color $RED 'Syncthing daemon never came up; skipping configuration.'
    return 1
  fi

  print_with_color $GREEN 'Applying LAN-only network posture'
  syncthing cli config options global-ann-enabled set false
  syncthing cli config options local-ann-enabled set true
  syncthing cli config options relays-enabled set false
  syncthing cli config options natenabled set false
  syncthing cli config options uraccepted set -- -1

  if [ ! -d "$VAULT" ]; then
    print_with_color $YELLOW "$VAULT not present; skipping folder setup."
    return 0
  fi

  if syncthing cli config folders list | grep -qx "$FOLDER_ID"; then
    print_with_color $GREEN "Folder '$FOLDER_ID' already configured"
  else
    print_with_color $GREEN "Adding $VAULT as '$FOLDER_ID'"
    syncthing cli config folders add --id "$FOLDER_ID" --label 'Obsidian Vault' --path "$VAULT"
  fi

  # Keep 10 old copies of anything overwritten by a remote change. Cheap
  # insurance against a bad sync eating a note.
  syncthing cli config folders "$FOLDER_ID" versioning type set simple
  syncthing cli config folders "$FOLDER_ID" versioning params set keep 10
  # Permissions differ across macOS/Linux/Android and aren't worth syncing.
  syncthing cli config folders "$FOLDER_ID" ignore-perms set true

  print_with_color $GREEN "This device's ID:"
  syncthing cli show system | jq -r .myID
}

function setup_syncthing() {
  if is_mac; then
    install_package syncthing
    brew services start syncthing
  else
    yay_sync syncthing
    systemctl --user enable --now syncthing.service
  fi

  configure_syncthing

  print_with_color $GREEN 'Next steps:'
  print_with_color $GREEN '  1. Run this script on every device (Android: F-Droid "Syncthing-Fork")'
  print_with_color $GREEN '  2. Pair each device with the hub using the IDs printed above'
  print_with_color $GREEN "  3. Share folder '$FOLDER_ID' from the hub; accept on each device"
  print_with_color $GREEN '  4. Folder ID must match everywhere, or they will not link up'
  print_with_color $GREEN '  5. Web UI: http://localhost:8384'
}

print_with_color $YELLOW 'Setup Syncthing? (y/n)'
read yn
case $yn in
  yes|Yes|YES|y|Y ) setup_syncthing;;
  * ) print_with_color $GREEN 'skipping...';;
esac
