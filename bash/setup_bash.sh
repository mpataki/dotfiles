. lib/helpers.sh

function write_bashrc() {
  print_with_color $GREEN "writing $HOME/.bashrc"

  echo ". `pwd`/bash/bashrc" > $HOME/.bashrc
}

function write_bash_profile() {
  print_with_color $GREEN "writing $HOME/.bash_profile"

  # login shells (mac Terminal, ssh) read .bash_profile, not .bashrc
  echo '[ -r "$HOME/.bashrc" ] && . "$HOME/.bashrc"' > $HOME/.bash_profile
}

function setup_bash() {
  if [ -e $HOME/.bashrc ]; then
    print_with_color $YELLOW "$HOME/.bashrc already exists. Do you want to override it? (yes/no)"
    read yn
    case $yn in
      yes|Yes|YES|y|Y ) write_bashrc;;
      * ) print_with_color $GREEN 'skipping...';;
    esac
  else
    write_bashrc
  fi

  if [ -e $HOME/.bash_profile ]; then
    print_with_color $YELLOW "$HOME/.bash_profile already exists. Do you want to override it? (yes/no)"
    read yn
    case $yn in
      yes|Yes|YES|y|Y ) write_bash_profile;;
      * ) print_with_color $GREEN 'skipping...';;
    esac
  else
    write_bash_profile
  fi
}

print_with_color $YELLOW 'Setup bash? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|y|Y ) setup_bash;;
  * ) print_with_color $GREEN 'skipping...';;
esac
