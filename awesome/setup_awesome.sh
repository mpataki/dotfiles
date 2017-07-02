
function setup_awesome() {
  pacman_sync awesome

  config_dir=$HOME/.config/awesome

  [ -e $config_dir ] || mkdir -p $config_dir
  check_and_link_file `pwd`/awesome/rc.lua $config_dir/rc.lua
  check_and_link_file `pwd`/awesome/themes/ $config_dir/

  git_clone 'https://github.com/blueyed/awesome-cyclefocus' $config_dir/cyclefocus
}

print_with_color $YELLOW 'Setup AwesomeWM? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|y|Y ) setup_awesome;;
  * ) print_with_color $GREEN 'skipping...';;
esac

