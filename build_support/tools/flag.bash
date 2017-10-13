#!/usr/bin/env bash

BASEDIR=$(dirname "$0")

DNAME="$1:$2"
FNAME=$($BASEDIR/dname_to_fname.bash "$DNAME")

docker inspect "$DNAME" >/dev/null 2>&1
if [ "$?" == "0" ]; then
  TZ=GMT touch -t $(docker inspect -f '{{.Created}}' "$DNAME" | awk -F. '{print $1}' | sed 's/[-T]//g' | sed 's/://' | sed 's/:/./') $FNAME
else
  rm -f $FNAME
fi
