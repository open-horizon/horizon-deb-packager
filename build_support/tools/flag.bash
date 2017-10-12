#!/usr/bin/env bash

NAME=$1
ARCH=$2

function fc() {
  s1="$(echo "$1" | sed 's,:,_,g')"
  s2="$(echo "$s1" | sed 's,/,-,g')"

  echo $s2
}

if docker inspect $NAME >/dev/null 2>&1
then
  TZ=GMT touch -t $(docker inspect -f '{{.Created}}' $NAME | awk -F. '{print $1}' | sed 's/[-T]//g' | sed 's/://' | sed 's/:/./') $(fc ${NAME})-${ARCH}.flag
else
  rm -f $(fc ${NAME})-${ARCH}.flag
fi
