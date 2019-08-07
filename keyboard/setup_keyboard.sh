#! /bin/bash

. lib/helpers.sh

function setup_keyboard() {
  yaourt_sync interception-caps2esc

  if ! [[ `grep caps2esc /etc/udevmon.yaml` ]]; then
    sudo touch /etc/udevmon.yaml

    sudo tee /etc/udevmon.yaml <<- EOM
- JOB: "intercept -g \$DEVNODE | caps2esc | uinput -d \$DEVNODE"
  DEVICE:
    EVENTS:
      EV_KEY: [KEY_CAPSLOCK, KEY_ESC]
EOM

    sudo systemctl enable udevmon
    print_with_color $YELLOW 'reboot for keyboard changes to take effect';;
  fi
}

print_with_color $YELLOW 'Setup keyboard? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_keyboard;;
  * ) print_with_color $GREEN 'skipping...';;
esac
