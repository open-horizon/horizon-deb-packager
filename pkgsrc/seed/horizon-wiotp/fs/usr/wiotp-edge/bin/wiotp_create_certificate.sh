#!/bin/bash

# A shell script that creates:
#
#    1. A CA certificate and key
#    2. A server key and certificate signed by tha above CA certificate for the local broker
#    3. A server key and certificate signed by tha above CA certificate for the edge-connector

# Insure that openssl is installed on the edge node
OPENSSL_PATH=$(command -v openssl)
if [ "${OPENSSL_PATH}" = "" ]; then
  echo "The openssl command, which is required by this shell script, is not installed on this system."
  exit 99
fi

# Read the config file for the persistence root directory
if [ -z ${1+x} ]; then
  CONFIG_FILE=/etc/wiotp-edge/edge.conf
else
  CONFIG_FILE=$1
fi

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
[ req_distinguished_name ]
    C                      = $COUNTRY
    ST                     = CAState
    L                      = CACity
    O                      = CAOrg
    OU                     = Edge Node
    CN                     = localhost
    emailAddress           = some@thing
[ v3_ca ]
    
EOF

# Create a configuration file to create the certificate requests
sed /\$COUNTRY/s//${COUNTRY}/ <<'EOF' > req.conf
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
[ v3_ca ]
    
EOF

# Get the password for the CA key file
CA_PASSWORD=$1
if [ -z $CA_PASSWORD ]; then
  read -s -p "Enter password for the CA key file: " CA_PASSWORD
  echo
  if [[ ${#CA_PASSWORD} -lt 4 ]]; then
      echo "The CA file password was less then four characters long"
      exit
  fi
  read -s -p "Verify the password for the CA key file: " CA_PASSWORD_VERIFY
  echo
  if [[ ${CA_PASSWORD} != ${CA_PASSWORD_VERIFY} ]]; then
      echo "The password for the CA file didn't verify"
      exit
  fi
else
  echo "** Generating certificates with default values and device token as the private key password." 
  echo "** Use /var/wiotp-edge/persist/createCertificate.sh to generate certificates with new parameters."   
  echo ""
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
echo "${CA_PASSWORD}" | openssl genrsa -aes256 -passout stdin -out ${BROKER_DIR}/ca/ca.key.pem 4096 
chmod 400 ${BROKER_DIR}/ca/ca.key.pem

echo "${CA_PASSWORD}" | openssl req -key ${BROKER_DIR}/ca/ca.key.pem  -new -x509 \
                                         -days 7300 -sha256 -extensions v3_ca \
                                         -out ${BROKER_DIR}/ca/ca.cert.pem -passin stdin \
                                         -config ca.conf
chmod 444 ${BROKER_DIR}/ca/ca.cert.pem


# Generating the key and certificate for the local broker
openssl genrsa -aes256 -passout pass:passw0rd -out key.pem 2048

openssl rsa -in key.pem -passin pass:passw0rd -out ${BROKER_DIR}/certs/broker_key.pem
chmod 400 ${BROKER_DIR}/certs/broker_key.pem

openssl req -new -key ${BROKER_DIR}/certs/broker_key.pem -out ${BROKER_DIR}/certs/broker.csr \
            -config req.conf

echo "${CA_PASSWORD}" | openssl x509 -req -in ${BROKER_DIR}/certs/broker.csr -days 500 -sha256 \
                                     -CA ${BROKER_DIR}/ca/ca.cert.pem -CAkey ${BROKER_DIR}/ca/ca.key.pem \
                                     -CAcreateserial -out ${BROKER_DIR}/certs/broker_cert.pem \
                                     -passin stdin

chmod 444 ${BROKER_DIR}/certs/broker_cert.pem


# Generating the key and certificate for the edge-connector
openssl genrsa -aes256 -passout pass:passw0rd -out key.pem 2048

openssl rsa -in key.pem -passin pass:passw0rd -out ${DC_DIR}/certs/key.pem
chmod 400 ${DC_DIR}/certs/key.pem

openssl req -new -key ${DC_DIR}/certs/key.pem -out ${DC_DIR}/certs/cert.csr \
            -config req.conf

echo "${CA_PASSWORD}" | openssl x509 -req -in ${DC_DIR}/certs/cert.csr -days 500 -sha256 \
                                     -CA ${BROKER_DIR}/ca/ca.cert.pem -CAkey ${BROKER_DIR}/ca/ca.key.pem \
                                     -CAcreateserial -out ${DC_DIR}/certs/cert.pem \
                                     -passin stdin
chmod 444 ${DC_DIR}/certs/cert.pem

cp ${BROKER_DIR}/ca/ca.cert.pem ${DC_DIR}/ca/ca.pem
rm key.pem req.conf ca.conf