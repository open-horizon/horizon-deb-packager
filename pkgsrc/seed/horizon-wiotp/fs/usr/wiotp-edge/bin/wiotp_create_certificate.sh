#!/bin/bash

# A shell script that creates:
#
#    1. A CA certificate and key
#    2. A server key and certificate signed by tha above CA certificate for the local broker
#    3. A server key and certificate signed by tha above CA certificate for the edge-connector
#

usage() {
    cat <<EOF
Usage: $0 [options] 

Arguments:

  -h, --help
    Display this usage message and exit.

  -v, --verbose
    Verbose output

  -c <val>, --configFile <val>, --configFile=<val>
    (Optional) Edge config file to be used. If not provided /etc/wiotp-edge/edge.conf will be used by default.

  -p <val>, --caKeyPassword <val>, --caKeyPassword=<val>
    (Optional) CA Key password. If not provide user will be prompted for one. 

  -cn <val>, --edgeConnectorCN <val>, --edgeConnectorCN=<val>
    (Optional) CN to be used when generating the server certificate for the edge-connector. 
    If not provided one will be generated based on the network interfaces definition.

EOF
}

# handy logging and error handling functions
log() { printf '%s\n' "$*"; }
error() { log "ERROR: $*" >&2; }
fatal() { error "$*"; exit 1; }
usage_fatal() { error "$*"; usage >&2; exit 1; }

while [ "$#" -gt 0 ]; do
    arg=$1
    case $1 in
        # convert "--opt=the value" to --opt "the value".
        # the quotes around the equals sign is to work around a
        # bug in emacs' syntax parsing
        --*'='*) shift; set -- "${arg%%=*}" "${arg#*=}" "$@"; continue;;
        -c|--configFile) shift; CONFIG_FILE=$1;;
        -p|--caKeyPassword) shift; CA_PASSWORD=$1;;
        -cn|--edgeConnectorCN) shift; CN_ADDRESS_PARAM=$1;;
        -v|--verbose) VERBOSE=true;;        
        -h|--help) usage; exit 0;;
        -*) usage_fatal "unknown option: '$1'";;
        *) break;; # reached the list of file names
    esac
    shift || usage_fatal "option '${arg}' requires a value"
done

logIfVerbose() {
  if [ ! -z $VERBOSE ]; then
    log $1
  fi
}

function checkrc {
  if [[ $1 -ne 0 ]]; then
    log "Last command exited with rc $1, exiting."
    if [[ ! -z $2 ]]; then    
      fatal "$2"
    fi
  fi
}

# For Debug
#echo CONFIG_FILE=$CONFIG_FILE
#echo CA_PASSWORD=$CA_PASSWORD
#echo CN_ADDRESS_PARAM=$CN_ADDRESS_PARAM

# Insure that openssl is installed on the edge node
OPENSSL_PATH=$(command -v openssl)
if [ "${OPENSSL_PATH}" = "" ]; then
  fatal "The openssl command, which is required by this shell script, is not installed on this system."
fi

if [ -z $CN_ADDRESS_PARAM ]; then
  EXTRA_SUBJECT_NAMES=""
else
  IP_ADDRESS_REGEX='^(0*(1?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))\.){3}'
  IP_ADDRESS_REGEX+='0*(1?[0-9]{1,2}|2([‌​0-4][0-9]|5[0-5]))$'
  if [[ ${CN_ADDRESS_PARAM} =~ ${IP_ADDRESS_REGEX} ]]; then
    EXTRA_SUBJECT_NAMES="IP:${CN_ADDRESS_PARAM}, "
  else
    EXTRA_SUBJECT_NAMES="DNS:${CN_ADDRESS_PARAM}, "
  fi
fi

# get list of network addresses on this computer
ADDRESSES=()

if [ "Linux" = "$(uname)" ]; then
  
  ADDRESS=""
  ACTIVE=""
  while read -r LINE; do
    WORDS=($LINE)
    PREFIX="${WORDS[0]%:}"
    if [[ "${PREFIX}" =~ ^[0-9]+$ ]]; then
      if [ "${ADDRESS}" != "" ] && [ "${ACTIVE}" != "" ]; then
        ADDRESSES+=($ADDRESS)
        ADDRESS=""
        ACTIVE=""
      fi
      if [ "${WORDS[8]}" = "UP" ]; then
        ACTIVE="Y"
      fi
    elif [ "${WORDS[0]}" = "inet" ]; then
      ADDRESS="${WORDS[1]%/*}"
    fi
  done < <(ip address)

  if [ "${ADDRESS}" != "" ] && [ "${ACTIVE}" != "" ]; then
    ADDRESSES+=($ADDRESS)
  fi

elif [ "Darwin" = "$(uname)" ]; then

  for INTERFACE in $(ifconfig -l) ; do
    ADDRESS=""
    ACTIVE=""
    while read -r WORD1 WORD2 REST; do
      if [ "${WORD1}" = "inet" ]; then
        ADDRESS="${WORD2}"
      elif [ "${WORD1}" = "status:" ] && [ "${WORD2}" = "active" ]; then
        ACTIVE="Y"
      fi  
    done < <(ifconfig ${INTERFACE})
    if [ "${ADDRESS}" != "" ] && [ "${ACTIVE}" != "" ]; then
      ADDRESSES+=($ADDRESS)
    fi
  done

else
  fatal "You are running this script on an unsupported Operating system."
fi

ADDRESS_COUNT=${#ADDRESSES[@]}
if [ $ADDRESS_COUNT -eq 0 ]; then
  if [ -z $CN_ADDRESS_PARAM ]; then
    log "No network interfaces were discovered and neither the"
    log "-cn parameter nor the --edgeConnectorCN parameter was specified."
    log "Rerun after fixing the network interfaces or specify"
    log "either the -cn parameter or the --edgeConnectorCN parameter."
    exit 1
  else
    CN_ADDRESS=${CN_ADDRESS_PARAM}
  fi
else
  for ADDRESS in ${ADDRESSES[@]}; do
    if [ -z ${CN_ADDRESS} ]; then
      CN_ADDRESS=${ADDRESS}
    else
      EXTRA_SUBJECT_NAMES="${EXTRA_SUBJECT_NAMES}IP:${ADDRESS}, "
    fi
  done
fi

# Read the config file for the persistence root directory
if [ -z $CONFIG_FILE ]; then
  CONFIG_FILE=/etc/wiotp-edge/edge.conf  
fi

logIfVerbose "Config File: $CONFIG_FILE will be used."

PERSIST_ROOT_DIRECTORY=/var/wiotp-edge/persist

while read -r LINE; do

  if [ "${LINE}" != "" ] && [ "${LINE:0:1}" != "#" ]; then
    FIELDS=($LINE)

    if [ "${FIELDS[0]}" == "PersistenceRootPath" ] && [ "${FIELDS[1]}" != "" ]; then
      PERSIST_ROOT_DIRECTORY=${FIELDS[1]}
    fi
  fi

done < ${CONFIG_FILE}

# Determine the country based on the locale for the time
if [ "Darwin" = "$(uname)" ]; then
   COUNTRY=US
else
   COUNTRY=$(echo "${LC_TIME}" | awk '{ print substr( $0, 4, 2 ) }')
   if [ "${COUNTRY}" == "" ]; then
      COUNTRY=US
   fi
fi

# Create a configuration file to create the CA
sed /\$COUNTRY/s//${COUNTRY}/ <<'EOF' > ca.conf
[ req ]
    default_bits           = 2048
    default_keyfile        = key.pem
    distinguished_name     = req_distinguished_name
    prompt                 = no
    output_password        = 
    req_extensions         = v3_ca
[ req_distinguished_name ]
    C                      = $COUNTRY
    ST                     = CAState
    L                      = CACity
    O                      = CAOrg
    OU                     = Edge Node
    CN                     = localhost
    emailAddress           = some@thing
[ v3_ca ]
    basicConstraints       = CA:true
    
EOF

# Create a configuration file to create the certificate request for the broker
sed /\$COUNTRY/s//${COUNTRY}/ <<'EOF' > broker.conf
[ req ]
    default_bits           = 2048
    default_keyfile        = key.pem
    distinguished_name     = req_distinguished_name
    prompt                 = no
    output_password        =
[ req_distinguished_name ]
    C                      = $COUNTRY
    ST                     = SomeState
    L                      = SomeCity
    O                      = SomeOrg
    OU                     = Edge Node
    CN                     = localhost
    emailAddress           = some@thing
    
EOF

# Create a configuration file to create the certificate request for the connector
sed "/\COUNTRY/s//${COUNTRY}/; /\CN_ADDRESS/s//${CN_ADDRESS}/g; /\EXTRA_SUBJECT_NAMES/s//${EXTRA_SUBJECT_NAMES}/" <<'EOF' > connector.conf
[ req ]
    default_bits           = 2048
    default_keyfile        = key.pem
    distinguished_name     = req_distinguished_name
    prompt                 = no
    output_password        =
    req_extensions         = v3_req
[ req_distinguished_name ]
    C                      = COUNTRY
    ST                     = SomeState
    L                      = SomeCity
    O                      = SomeOrg
    OU                     = Edge Node
    CN                     = CN_ADDRESS
    emailAddress           = some@thing
[ v3_req ]
    subjectAltName = IP:CN_ADDRESS, EXTRA_SUBJECT_NAMES  DNS:localhost, DNS:localhost, IP:127.0.0.1
    
EOF

# Get the password for the CA key file
if [ -z $CA_PASSWORD ]; then
  read -s -p "Enter password for the CA key file: " CA_PASSWORD
  if [[ ${#CA_PASSWORD} -lt 4 ]]; then
      fatal "The CA file password was less then four characters long"
  fi
  read -s -p "Verify the password for the CA key file: " CA_PASSWORD_VERIFY
  echo
  if [[ ${CA_PASSWORD} != ${CA_PASSWORD_VERIFY} ]]; then
      fatal "The password for the CA file didn't verify"
  fi
  echo ""
else
  logIfVerbose "The CA Private key is configured to use the device credential password by default." 
  logIfVerbose "Use wiotp_create_certificate tool to manually generate certificates with a new key password"   
  logIfVerbose "and restart all edge core iot components"
fi

BROKER_DIR=${PERSIST_ROOT_DIRECTORY}/broker
DC_DIR=${PERSIST_ROOT_DIRECTORY}/dc

# Create directories to hold files
mkdir -p ${BROKER_DIR}/ca
mkdir -p ${BROKER_DIR}/certs
mkdir -p ${DC_DIR}/ca
mkdir -p ${DC_DIR}/certs

# Cleanup old files in case they exist
rm -f ${BROKER_DIR}/ca/ca.key.pem ${BROKER_DIR}/ca/ca.cert.pem
rm -f ${BROKER_DIR}/certs/broker_key.pem ${BROKER_DIR}/certs/broker_cert.pem
rm -f ${DC_DIR}/certs/key.pem ${DC_DIR}/certs/cert.pem ${DC_DIR}/ca/ca.pem

# Generating the key and certificate for the CA
output=$(echo "${CA_PASSWORD}" | openssl genrsa -aes256 -passout stdin -out ${BROKER_DIR}/ca/ca.key.pem 4096 2>&1)
checkrc $? "$output"
logIfVerbose "$output"


chmod 400 ${BROKER_DIR}/ca/ca.key.pem

output=$(echo "${CA_PASSWORD}" | openssl req -key ${BROKER_DIR}/ca/ca.key.pem  -new -x509 \
                                         -days 7300 -sha256 -extensions v3_ca \
                                         -out ${BROKER_DIR}/ca/ca.cert.pem -passin stdin \
                                         -config ca.conf 2>&1)
checkrc $? "$output"
logIfVerbose "$output"
                                         
chmod 444 ${BROKER_DIR}/ca/ca.cert.pem


# Generating the key and certificate for the local broker
output=$(openssl genrsa -aes256 -passout pass:passw0rd -out key.pem 2048 2>&1)
checkrc $? "$output"
logIfVerbose "$output"

output=$(openssl rsa -in key.pem -passin pass:passw0rd -out ${BROKER_DIR}/certs/broker_key.pem 2>&1)
checkrc $? "$output"
logIfVerbose "$output"

chmod 400 ${BROKER_DIR}/certs/broker_key.pem

output=$(openssl req -new -key ${BROKER_DIR}/certs/broker_key.pem -out ${BROKER_DIR}/certs/broker.csr \
            -config broker.conf 2>&1)
checkrc $? "$output"
logIfVerbose "$output"

output=$(echo "${CA_PASSWORD}" | openssl x509 -req -in ${BROKER_DIR}/certs/broker.csr -days 500 -sha256 \
                                     -CA ${BROKER_DIR}/ca/ca.cert.pem -CAkey ${BROKER_DIR}/ca/ca.key.pem \
                                     -CAcreateserial -out ${BROKER_DIR}/certs/broker_cert.pem \
                                     -passin stdin 2>&1)
checkrc $? "$output"
logIfVerbose "$output"

chmod 444 ${BROKER_DIR}/certs/broker_cert.pem


# Generating the key and certificate for the edge-connector
output=$(openssl genrsa -aes256 -passout pass:passw0rd -out key.pem 2048 2>&1)
checkrc $? "$output"
logIfVerbose "$output"

output=$(openssl rsa -in key.pem -passin pass:passw0rd -out ${DC_DIR}/certs/key.pem 2>&1)
checkrc $? "$output"
logIfVerbose "$output"

chmod 400 ${DC_DIR}/certs/key.pem

output=$(openssl req -new -key ${DC_DIR}/certs/key.pem -out ${DC_DIR}/certs/cert.csr \
            -config connector.conf 2>&1)
checkrc $? "$output"
logIfVerbose "$output"

output=$(echo "${CA_PASSWORD}" | openssl x509 -req -in ${DC_DIR}/certs/cert.csr -days 500 -sha256 \
                                     -CA ${BROKER_DIR}/ca/ca.cert.pem -CAkey ${BROKER_DIR}/ca/ca.key.pem \
                                     -CAcreateserial -out ${DC_DIR}/certs/cert.pem \
				     -extfile connector.conf -extensions v3_req \
                                     -passin stdin 2>&1)
checkrc $? "$output"
logIfVerbose "$output"

chmod 444 ${DC_DIR}/certs/cert.pem

cp ${BROKER_DIR}/ca/ca.cert.pem ${DC_DIR}/ca/ca.pem
rm key.pem broker.conf connector.conf ca.conf
