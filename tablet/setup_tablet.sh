#! /bin/bash

. lib/helpers.sh

function setup_tablet() {
  # stylus
  pacman_sync xf86-input-wacom

  # screen rotation
  pacman_sync iio-sensor-proxy-git
  pacman_sync screenrotator-git
  pacman_sync xf86-input-evdev
  yay_sync xinput_calibrator
  yay_sync touchegg

  print_with_color $YELLOW 'Run xinput_calibrator to calibrate the touch screen'
}

print_with_color $YELLOW 'Setup tablet mode? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_tablet;;
  * ) print_with_color $GREEN 'skipping...';;
esac
