#!/bin/bash
. lib/helpers.sh

function setup_redis() {
  # Note: redis-stack is installed via tap, not regular brew formula
  # brew tap redis-stack/redis-stack
  # brew install redis-stack-server

  if ! [[ `which redis-stack-server` ]]; then
    print_with_color $YELLOW "redis-stack-server not found. Install it? (y/n)"
    read yn
    case $yn in
      yes|Yes|YES|y|Y )
        brew tap redis-stack/redis-stack
        brew install redis-stack-server
        ;;
      * ) print_with_color $GREEN 'skipping installation...';;
    esac
  fi

  # Link config file
  check_and_link_file `pwd`/redis/redis-stack.conf /opt/homebrew/etc/redis-stack.conf

  # Link LaunchAgent plist
  mkdir -p $HOME/Library/LaunchAgents
  check_and_link_file `pwd`/redis/com.redis.redis-stack.plist $HOME/Library/LaunchAgents/com.redis.redis-stack.plist

  # Create log directory
  mkdir -p /opt/homebrew/var/log

  # Load the launch agent
  print_with_color $YELLOW "Load redis-stack launch agent now? (y/n)"
  read yn
  case $yn in
    yes|Yes|YES|y|Y )
      launchctl unload $HOME/Library/LaunchAgents/com.redis.redis-stack.plist 2>/dev/null
      launchctl load $HOME/Library/LaunchAgents/com.redis.redis-stack.plist
      print_with_color $GREEN "Redis Stack service loaded"
      ;;
    * ) print_with_color $GREEN 'skipping service load...';;
  esac
}

print_with_color $YELLOW 'Setup Redis Stack? (y/n)'
read yn
case $yn in
  yes|Yes|YES|y|Y ) setup_redis;;
  * ) print_with_color $GREEN 'skipping...';;
esac
