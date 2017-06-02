#!/bin/bash

scriptname=$0

function usage {
    echo "usage: $scriptname [-h]"
    echo "  -h      display help"
    echo -e "\nThe COMMON  environment variable MUST be set to the location of your ethereum credentials."
    echo "The TARFILE environment variable MAY be set of the name of the resulting tarred and gzipped archive. The default is ethcreds.tar.gz"
    exit_with_code 1
}

function exit_with_code() {
    popd > /dev/null
    exit $1
}

COMMON=${COMMON:-/var/horizon/common}
TARFILE=${TARFILE:-$PWD/ethcreds.tar.gz}

while getopts :h option
do
    case "${option}"
    in
        h) usage;;
    esac
done

if [[ ! -d $COMMON ]]; then
    echo "$scriptname: Ethereum credential location $COMMON does not exist."
    usage
fi

echo "$scriptname: Looking for ethereum credential files in $COMMON"
pushd $COMMON > /dev/null

if ! /bin/ls .*/keystore >/dev/null 2>&1; then
    echo "$scriptname: Ethereum keystore not found within $COMMON."
    usage
fi

if ! /bin/ls */accounts >/dev/null 2>&1; then
    echo "$scriptname: Horizon ethereum accounts file not found within $COMMON."
    usage
fi

if ! /bin/ls */passwd >/dev/null 2>&1; then
    echo "$scriptname: Horizon ethereum passwd file not found within $COMMON."
    usage
fi

echo "$scriptname: Creating archive file $TARFILE containing ethereum credentials."
tar czvf $TARFILE */accounts */passwd .*/keystore

if [ $? -ne 0 ]; then 
    echo "$scriptname: Could not create archive of collected files."
    exit_with_code 1
else
    echo "$scriptname: Completed successfully"
    exit_with_code 0
fi
