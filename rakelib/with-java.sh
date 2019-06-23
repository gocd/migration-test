#!/usr/bin/env bash

function use_jdk() {
  if [ ! -f "${HOME}/.jabba/jabba.sh" ]; then
    curl -sL https://github.com/shyiko/jabba/raw/master/install.sh | bash
  fi
  source "${HOME}/.jabba/jabba.sh"
  jabba install "$1=$2"
  jabba use "$1"
}
use_jdk "openjdk@1.12.0" "tgz+https://download.java.net/java/GA/jdk12/GPL/openjdk-12_linux-x64_bin.tar.gz"

echo "JAVA HOME set to $JAVA_HOME"

exec "$@"
