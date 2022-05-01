#! /bin/bash

. lib/helpers.sh

function setup_keyboard() {
  yay_sync interception-tools

  here=`pwd`

  git_clone https://github.com/mpataki/caps2esc.git /tmp/caps2esc
  cd /tmp/caps2esc
  mkdir build
  cd build
  cmake ..
  make build
  sudo make install

  cd $here

  if ! [[ `grep caps2esc /etc/interception/udevmon.yaml` ]]; then
    sudo touch /etc/interception/udevmon.d/udevmon.yaml

    sudo tee /etc/interception/udevmon.d/udevmon.yaml <<- EOM
- JOB: "intercept -g \$DEVNODE | caps2esc | uinput -d \$DEVNODE"
  DEVICE:
    EVENTS:
      EV_KEY: [KEY_CAPSLOCK, KEY_ESC]
EOM

    sudo systemctl enable udevmon
    sudo systemctl restart udevmon
  fi
}

print_with_color $YELLOW 'Setup keyboard? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_keyboard;;
  * ) print_with_color $GREEN 'skipping...';;
esac
