#!/usr/bin/env bash

set -e

if [ "$#" -lt 3 ]; then
  (2> echo "Usage:\n$0 arch template_fname output_fname")
  exit 1
fi

ARCH="$1"
FNAME="$2"
DEST="$3"

golang_dl_url=""
from_image=""
# the default Docker instruction for architectures supported by it
node_install="RUN curl -sL https://deb.nodesource.com/setup_4.x | bash - \&\& apt-get install -y nodejs"

case "$ARCH" in
('armhf')
  from_image="arm32v7/ubuntu:16.04"
  node_install="RUN apt-get install -y nodejs npm"
  golang_arch="armv6l"
  ;;
('arm64')
  from_image="arm64v8/ubuntu:16.04"
  golang_arch="arm64"
  ;;
('amd64')
  from_image="ubuntu:16.04"
  golang_arch="amd64"
  ;;
('ppc64el')
  from_image="ppc64le/ubuntu:16.04"
  node_install="RUN apt-get install -y nodejs npm"
  golang_arch="ppc64le"
  ;;
(*)
  (>&2 echo "Unknown or unsupported architecture: $1")
  exit 1
  ;;
esac

golang_dl_url="https://storage.googleapis.com/golang/go1.9.1.linux-${golang_arch}.tar.gz"

sed "s,##from_image##,$from_image," "$FNAME" > "$DEST"
sed -i.bak "s,##arch##,$ARCH," "$DEST" && rm -f "$DEST".bak
sed -i.bak "s,##node_install##,$node_install," "$DEST" && rm -f "$DEST".bak
sed -i.bak "s,##golang_dl_url##,$golang_dl_url," "$DEST" && rm -f "$DEST".bak
