
function setup_gnupg() {
  pacman_sync gnupg
  pacman_sync pinentry
  pacman_sync pass

  if ! [ -d $HOME/.gnupg ]; then
    mkdir $HOME/.gnupg
  fi

  check_and_link_file `pwd`/gnupg/gpg.conf $HOME/.gnupg/gpg.conf
  check_and_link_file `pwd`/gnupg/gpg-agent.conf $HOME/.gnupg/gpg-agent.conf
  check_and_link_file `pwd`/gnupg/scdaemon.conf $HOME/.gnupg/scdaemon.conf

  systemctl start pcscd
  systemctl enable pcscd
  echo "recall: gpg needs it's keyring populated with the private key corresponding to the public key used to encrypt your password-store"
}

print_with_color $YELLOW 'Setup GnuPG? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|y|Y ) setup_gnupg;;
  * ) print_with_color $GREEN 'skipping...';;
esac

