#!/bin/bash

scriptname=$0

function usage {
    echo "usage: $scriptname [-h] <tar-file>"
    echo "  -h      display help"
    echo -e "\n<tar-file> is a gzipped tar archive containing the ethereum credentials."
    echo -e "\nThe COMMON  environment variable MUST be set to the location of your ethereum credentials."
    exit_with_code 1
}

function exit_with_code() {
    exit $1
}

COMMON=${COMMON:-/var/horizon/common}
TARFILE=${TARFILE:-$1}

if [[ -z $TARFILE ]]; then
    echo "$scriptname: Specify tar file containing ethereum credentials."
    usage
fi

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

echo "$scriptname: Opening credential archive $TARFILE, storing credentials in $COMMON"
tar xzvf $TARFILE -C $COMMON

if [[ $? -ne 0 ]]; then 
    echo "$scriptname: Could not unarchive credential files."
    exit_with_code 1
else
    echo "$scriptname: Completed successfully"
    exit_with_code 0
fi
