
function setup_gnupg() {
  # TODO: install gpg & deps (pinentry as well)

  if ! [ -d $USER_HOME/.gnupg ]; then
    mkdir $USER_HOME/.gnupg
  fi

  check_and_link_file `pwd`/gnupg/gpg.conf $USER_HOME/.gnupg/gpg.conf
  check_and_link_file `pwd`/gnupg/gpg-agent.conf $USER_HOME/.gnupg/gpg-agent.conf
}

print_with_color $YELLOW 'Setup GnuPG? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|y|Y ) setup_gnupg;;
  * ) print_with_color $GREEN 'skipping...';;
esac

