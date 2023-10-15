RED="\e[31m"
GREEN="\e[32m"
BLUE="\e[34m"
YELLOW="\e[33m"
WHITE="\e[37m"
NONE="\e[39m"

function print_with_color() {
  color=$1
  string=$2
  printf "$color$string$NONE\n"
}

function link_file() {
  source_file=$1
  destination=$2
  use_sudo=$3

  print_with_color $GREEN "linking $source_file to $destination"

  if [ -n $use_sudo ]; then
    sudo ln -sf "$source_file" "$destination"
  else
    ln -sf "$source_file" "$destination"
  fi
}

function check_and_link_file() {
  source_file=$1
  destination=$2
  use_sudo=$3

    if [ -f $source_file ] && [ -e $destination ]; then
    print_with_color $YELLOW "$destination already exists. Do you want to override it? (y/n)"
    read yn
    case $yn in
      yes|Yes|YES|y|Y )
        if [ -d "$destination" ]; then
          rm -rf "$destination"
        else
          rm "$destination"
        fi

        link_file "$source_file" "$destination" $use_sudo
        ;;
      * ) print_with_color $GREEN 'skipping...';;
    esac
  else
    link_file "$source_file" "$destination" $use_sudo
  fi
}

function git_clone() {
  repo=$1
  dest=$2

  if [ -e "$dest" ]; then
    print_with_color $YELLOW "$dest already present. Do you want to overwrite it? (y/n)"
    read yn
    case $yn in
      yes|Yes|YES|y|Y )
        rm -rf $dest
        ;;
      * ) print_with_color $GREEN 'skipping...'; return;;
    esac
  fi

  git clone --depth=1 "$repo" "$dest"
}

function pacman_sync() {
  package=$1

  if ! pacman -Q $package ; then
    print_with_color $YELLOW "Package '$package' not installed. Do you want to install it? (y/n)"

    read yn
    case $yn in
      yes|Yes|YES|y|Y )
        sudo pacman -Sy $package
        ;;
      * ) print_with_color $GREEN 'skipping...';;
    esac
  fi
}

function aur_install() {
  echo 'you probably want to be using yay install for AUR packages'

  package=$1
  git_url=$2
  dest=$HOME/builds/$package

  make -p $HOME/builds
  git_clone $git_url $dest

  cd $dest && makepkg -si && cd -
}

function yay_sync() {
  package=$1

  if ! yay -Q $package ; then
    print_with_color $YELLOW "Package '$package' not installed. Do you want to install it? (y/n)"

    read yn
    case $yn in
      yes|Yes|YES|y|Y )
        yay -Sy $package
        ;;
      * ) print_with_color $GREEN 'skipping...';;
    esac
  fi
}

function brew_install() {
  pacakge=$1

  if ! [[ `brew list | grep $package` ]]; then
    print_with_color $YELLOW "Package '$package' not installed. Do you want to install it? (y/n)"

    read yn
    case $yn in
      yes|Yes|YES|y|Y )
        brew install $package
        ;;
      * ) print_with_color $GREEN 'skipping...';;
    esac
  fi
}

function is_mac() {
  if [[ `uname | grep Darwin` ]]; then
    return 0
  else
    return 1
  fi
}

function install_package() {
  package=$1

  if is_mac; then
    brew_install $package;
  else
    yay_sync $package;
  fi
}
