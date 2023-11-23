#!/bin/bash

export NOTES_S3_BUCKET=note-store
export LOCAL_NOTE_STORE=$HOME/notes
export EDITOR=/opt/homebrew/bin/nvim
export BROWSER=/usr/bin/brave
export GPG_TTY=$(tty)
#export SPARK_HOME=/home/mat/code/spark-2.1.0-bin-hadoop2.7
#export SPARK_HOME=/home/mat/code/spark-2.4.3-bin-hadoop2.7
export SPARK_HOME=/home/mat/code/spark-3.1.1-bin-hadoop3.2

export PATH="/home/mat/code/kafka-3.2.0-src/bin/:$PATH"

export GRAALVM_HOME=/usr/lib/jvm/java-17-graalvm

# GH CLI
export CLICOLOR_FORCE=true

source $HOME/.env

