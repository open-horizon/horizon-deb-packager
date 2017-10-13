#!/usr/bin/env bash

echo "$(echo "$1" | sed 's,/,~,g' | sed 's,:,!,g').flag"
