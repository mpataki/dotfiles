#!/bin/bash
. lib/helpers.sh

function setup_misc_tools() {
  if is_mac; then
    install_package awscli
    install_package watch
  else
    pacman_sync base-devel
    pacman_sync cmake
    pacman_sync make
    pacman_sync openssh
    pacman_sync sshpass
    pacman_sync bind-tools
    yay_sync yubikey-manager-qt
    yay_sync albert
    yay_sync brave-bin
    yay_sync ksnip
    yay_sync net-tools
    yay_sync xfce4-terminal
    yay_sync visual-studio-code-bin
    yay_sync unzip

    yay_sync libserdes-git
    yay_sync yajl


    print_with_color $GREEN 'Setting the locale to en_US.UTF-8'
    localectl set-locale LANG=en_US.UTF-8
  fi

  install_package htop
  install_package wget
  install_package lsof
  install_package jq
  install_package ansible
  install_package netcat
  #install_package packer
  install_package tcpflow
  install_package k9s
  install_package grpcurl
  install_package mitmproxy
  install_package 1password
  install_package ctop
  install_package node
  install_package tree
  install_package 1password-cli
  install_package llvm # c++ debugger
  install_package zoxide
  install_package fzf
  install_package bufbuild/buf/buf buf
  install_package gnupg
  install_package direnv
  install_package go-task/tap/go-task task
  install_package mysql-client
  install_package yq

  if [[ -z `which atuin` ]]; then
    curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh
  fi
}

print_with_color $YELLOW 'Setup misc. tools? (yes/no)'
read yn
case $yn in
  yes|Yes|YES|Y|y ) setup_misc_tools;;
  * ) print_with_color $GREEN 'skipping...';;
esac
