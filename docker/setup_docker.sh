#!/bin/bash

function setup_docker() {
  pacman_sync docker
  pacman_sync docker-compose
  sudo mkdir -p /etc/docker
  check_and_link_file `pwd`/docker/docker.json /etc/docker/daemon.json
  sudo usermod -a -G docker $USER
  newgrp docker
  systemctl restart docker
}

print_with_color $YELLOW 'Setup docker? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_docker;;
  * ) print_with_color $GREEN 'skipping...';;
esac
