
function write_bashrc() {
  print_with_color $GREEN "writing $USER_HOME/.bash_profile"
  echo ". `pwd`/bash/bashrc" > $USER_HOME/.bashrc
}

function setup_bash(){
  if [ -e $USER_HOME/.bashrc ]; then
    print_with_color $YELLOW "$USER_HOME/.bashrc already exists. Do you want to override it? (yes/no)"
    read yn
    case $yn in
      yes|Yes|YES|y|Y ) write_bashrc;;
      * ) print_with_color $GREEN 'skipping...';;
    esac
  else
    write_bashrc
  fi

  pacman_sync bash-completion
}

print_with_color $YELLOW 'Setup Bash? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_bash;;
  * ) print_with_color $GREEN 'skipping...';;
esac

