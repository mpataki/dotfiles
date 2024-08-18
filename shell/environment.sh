#!/bin/bash

export EDITOR=/opt/homebrew/bin/nvim
#export GPG_TTY=$(tty)
export SPARK_HOME=/home/mat/code/spark-3.1.1-bin-hadoop3.2

export PATH="/home/mat/code/kafka-3.2.0-src/bin/:$PATH"

export GRAALVM_HOME=/usr/lib/jvm/java-17-graalvm

# hack.. not sure what's setting BROWSER right now
unset BROWSER

# GH CLI
export CLICOLOR_FORCE=true

source $HOME/.env

