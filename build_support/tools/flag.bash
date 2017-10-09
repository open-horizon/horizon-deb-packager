#!/usr/bin/env bash

NAME=$1
ARCH=$2

function fc() {
  if [ "$(echo "$1" | grep ':')" != "" ]; then
    echo "$1" | sed 's/:/_/'
  else
    echo "$1"
  fi
}

if docker inspect $NAME >/dev/null 2>&1
then
  TZ=GMT touch -t $(docker inspect -f '{{.Created}}' $NAME | awk -F. '{print $1}' | sed 's/[-T]//g' | sed 's/://' | sed 's/:/./') $(fc ${NAME})-${ARCH}.flag
else
  rm -f $(fc ${NAME})-${ARCH}.flag
fi
