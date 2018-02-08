# This scripts install the ANAX Horizon agent and configures it to run the WIoTP Edge IoT Core Worload
# 
# Pre-requisite to run:
#  wget
#  curl 
#  Openssl

#!/bin/bash

usage() {
    cat <<EOF
Usage: $0 [options] 

Arguments:
  
  -h, --help
    Display this usage message and exit.

  -v, --verbose
    Verbose output

  -o <val>, --org <val>, --org=<val>
    (Required) Organization Id.

  -dt <val>, --deviceType <val>, --deviceType=<val>
    (Required) Device or Gateway type.

  -di <val>, --deviceId <val>, --deviceId=<val>
    (Required) Device or Gateway Id.

  -dp <val>, --deviceToken <val>, --deviceToken=<val>
    (Required) Device or Gateway Token.

  -r <val>, --region <val>, --region=<val>
    (Optional) Organization Region: us | uk | ch | de | nl . Default is us.
    Use us for US South and East
    Use uk for United Kingdom
    Use ch for China
    Use de for Germany

  -dm <val>, --domain <val>, -domain=<val>
    (Optional) WIoTP internet domain. Default is internetofthings.ibmcloud.com.

  -cn <val>, --edgeCN <val>, -edgeCN=<val>
    (Optional) Common Name (CN) to be used when generating the Server Certificate for the Edge Connector.

  --cloudDisableCertCheck <true|false>, --cloudDisableCertCheck=<true|false>
    (Optional) Sets the CloudDisableCertCheck property for the Edge Connector configuration file. Using true will ignore non-trusted server certificates. 
    Enabling this property on production environments is not recommended.

  -shr, --skipHorizonRegistration
    (Optional) Performs all setup steps (internal certificate creation and hzn input json file preparation), without running hzn register
    Passing this parameter allows the user to edit hznEdgeCoreIoTInput.json and add specific workload variables.

  -f, --file
    (Optional) Merges a custom file (containing environment variable definitions for microservices and workloads) with hznEdgeCoreIoTInput.json
    The value passed to this parameter must contain the complete path to the file.

EOF
}

# handy logging and error handling functions
log() { printf '%s\n' "$*"; }
error() { log "ERROR: $*" >&2; }
fatal() { error "$*"; exit 1; }
usage_fatal() { error "$*"; usage >&2; exit 1; }

# Optional arguments
WIOTP_INSTALL_REGION="us"
WIOTP_INSTALL_DOMAIN="internetofthings.ibmcloud.com"

while [ "$#" -gt 0 ]; do
    arg=$1
    case $1 in
        # convert "--opt=the value" to --opt "the value".
        # the quotes around the equals sign is to work around a
        # bug in emacs' syntax parsing
        --*'='*) shift; set -- "${arg%%=*}" "${arg#*=}" "$@"; continue;;
        -o|--org) shift; WIOTP_INSTALL_ORGID=$1;;
        -dt|--deviceType) shift; WIOTP_INSTALL_DEVICE_TYPE=$1;;
        -di|--deviceId) shift; WIOTP_INSTALL_DEVICE_ID=$1;;
        -dp|--deviceToken) shift; WIOTP_INSTALL_DEVICE_TOKEN=$1;;
        -te|--testEnv) shift; WIOTP_INSTALL_TEST_ENV=$1;;
        -r|--region) shift; WIOTP_INSTALL_REGION=$1;;
        -dm|--domain) shift; WIOTP_INSTALL_DOMAIN=$1;;
        -cdc|--cloudDisableCertCheck) shift; CDCC_TEMP=$1;;
        -shr|--skipHorizonRegistration) SKIP_HORIZON_REGISTRATION=true;;
        -f|--file) shift; CUSTOM_HZN_INPUT_FILE=$1;;
        -cn|--edgeCN) shift; WIOTP_INSTALL_EDGE_CN=$1;;
        -h|--help) usage; exit 0;;
        -v|--verbose) VERBOSE='-v';;
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

# Check if a required option was not set
#if [[ -z $WIOTP_INSTALL_DEVICE_ID || -z  $WIOTP_INSTALL_DEVICE_TYPE || -z $WIOTP_INSTALL_DEVICE_ID  || -z $WIOTP_INSTALL_DEVICE_TOKEN ]]; then
if [[ -z $WIOTP_INSTALL_DEVICE_ID ]] || [[ -z $WIOTP_INSTALL_DEVICE_TYPE ]] || [[ -z $WIOTP_INSTALL_DEVICE_ID ]] || [[ -z $WIOTP_INSTALL_DEVICE_TOKEN ]]; then
  usage_fatal "Values for the following options are required: --org, --deviceType, --deviceId, --deviceToken"
fi
# Check valid regions
if [[ "${WIOTP_INSTALL_REGION}" != "us" && "${WIOTP_INSTALL_REGION}" != "uk" && "${WIOTP_INSTALL_REGION}" != "de" && "${WIOTP_INSTALL_REGION}" != "ch" && "${WIOTP_INSTALL_REGION}" != "nl" ]];then
    usage_fatal "Invalid region."
fi

WIOTP_INSTALL_EC_DISABLE_CERT_CHECK=false
case $CDCC_TEMP in
  (true)    WIOTP_INSTALL_EC_DISABLE_CERT_CHECK=true;;
esac

function checkrc {
	if [[ $1 -ne 0 ]]; then
		fatal "Last command exited with rc $1, exiting."
	fi
}

log "WIoTP Horizon agent setup start."

VAR_DIR="/var"
ETC_DIR="/etc"

if [ -z $WIOTP_INSTALL_TEST_ENV ]; then
  httpDomainPrefix=$WIOTP_INSTALL_ORGID
  httpDomain=$WIOTP_INSTALL_DOMAIN
  mqttDomainPrefix=$WIOTP_INSTALL_ORGID.messaging
  regionPrefix=$WIOTP_INSTALL_REGION
else
  httpDomainPrefix=$WIOTP_INSTALL_ORGID.$WIOTP_INSTALL_TEST_ENV
  httpDomain=$WIOTP_INSTALL_TEST_ENV.$WIOTP_INSTALL_DOMAIN
  mqttDomainPrefix=$WIOTP_INSTALL_ORGID.messaging.$WIOTP_INSTALL_TEST_ENV
  regionPrefix=$WIOTP_INSTALL_REGION.$WIOTP_INSTALL_TEST_ENV
fi

# Check if domain exists
logIfVerbose "Checking domain..."
output=$(curl -Is -o /dev/null -w "%{http_code}" https://$httpDomain)
if [[ $output -ne 200 ]]; then
  fatal "Invalid domain $httpDomain. Could not reach https://$httpDomain"
fi

logIfVerbose "Domain is valid."

# Check if org exists
logIfVerbose "Checking org..."
output=$(curl -Is -o /dev/null -w "%{http_code}" https://$httpDomainPrefix.$WIOTP_INSTALL_DOMAIN)
if [[ $output -ne 200 ]]; then
  fatal "Invalid org $WIOTP_INSTALL_ORGID. Could not reach https://$httpDomainPrefix.$WIOTP_INSTALL_DOMAIN. Check the value passed to --org"
fi

logIfVerbose "Org is valid."

logIfVerbose "Checking device id and device type..."
output=$(curl -s -o /dev/null -w "%{http_code}" -u "$WIOTP_INSTALL_ORGID/g@$WIOTP_INSTALL_DEVICE_TYPE@$WIOTP_INSTALL_DEVICE_ID:$WIOTP_INSTALL_DEVICE_TOKEN" https://$httpDomainPrefix.$WIOTP_INSTALL_DOMAIN/api/v0002/edgenode/orgs/$WIOTP_INSTALL_ORGID/nodes/g@$WIOTP_INSTALL_DEVICE_TYPE@$WIOTP_INSTALL_DEVICE_ID)
if [[ $output -ne 200 ]]; then
  log "ERROR: Could not access device $WIOTP_INSTALL_DEVICE_ID of type $WIOTP_INSTALL_DEVICE_TYPE."
  log "  Troubleshooting:"
  log "    1. Check if the device type was created in Watson IoT Platform."
  log "    2. Make sure that when device type was created, 'Gateway' type was selected and 'Edge Capabilities' toggle was enabled."
  log "    3. Check if a device was created under that device type."
  log "    4. Make sure the device credentials are correct."
  exit 1
fi

logIfVerbose "Device id, device type and device authentication token are valid."

# Read the json object in /etc/horizon/anax.json
anaxJson=$(jq '.' $ETC_DIR/horizon/anax.json)
checkrc $?

# Change the value of ExchangeURL in /etc/horizon/anax.json
anaxJson=$(jq ".Edge.ExchangeURL = \"https://$httpDomainPrefix.$WIOTP_INSTALL_DOMAIN/api/v0002/edgenode/\" " <<< $anaxJson)
checkrc $?

# Write the new json back to /etc/horizon/anax.json
echo "$anaxJson" > $ETC_DIR/horizon/anax.json

# Restart the horizon service so that the new exchange URL can take effect
logIfVerbose "Restarting Horizon service ..."
systemctl restart horizon.service

edge_conf_template_path="${ETC_DIR}/wiotp-edge/edge.conf.template"
edge_conf_path="${ETC_DIR}/wiotp-edge/edge.conf"

# Create the edge.conf using the edge.conf.template
cp $edge_conf_template_path $edge_conf_path

# Adjusting edge.conf for enabling/disabling cloud server certificate checks
logIfVerbose "Setting $edge_conf_path[EC.CloudDisableCertCheck=$WIOTP_INSTALL_EC_DISABLE_CERT_CHECK]"
sed -i.bak "/EC.CloudDisableCertCheck.*/c\EC.CloudDisableCertCheck $WIOTP_INSTALL_EC_DISABLE_CERT_CHECK" $edge_conf_path
rm $edge_conf_path.bak

# Create the hznEdgeCoreIoTInput.json using the hznEdgeCoreIoTInput.json.template and user inputs
logIfVerbose "Creating hzn config input file ..."

CORE_IOT_HZN_INPUT_FILE=$ETC_DIR/wiotp-edge/hznEdgeCoreIoTInput.json

emptyConfigJson=$(jq '.' ${CORE_IOT_HZN_INPUT_FILE}.template)
checkrc $?

configJson=$(jq ".global[0].sensor_urls[0] = \"https://$regionPrefix.$WIOTP_INSTALL_DOMAIN/api/v0002/horizon-image/common\" " <<< $emptyConfigJson)
checkrc $?

configJson=$(jq ".global[0].variables.username = \"$WIOTP_INSTALL_ORGID/g@$WIOTP_INSTALL_DEVICE_TYPE@$WIOTP_INSTALL_DEVICE_ID\" " <<< $configJson)
checkrc $?

configJson=$(jq ".global[0].variables.password = \"$WIOTP_INSTALL_DEVICE_TOKEN\" " <<< $configJson)
checkrc $?

configJson=$(jq ".microservices[0].variables.WIOTP_DEVICE_AUTH_TOKEN = \"$WIOTP_INSTALL_DEVICE_TOKEN\" " <<< $configJson)
checkrc $?

configJson=$(jq ".microservices[0].variables.WIOTP_DOMAIN = \"$mqttDomainPrefix.$WIOTP_INSTALL_DOMAIN\" " <<< $configJson)
checkrc $?

configJson=$(jq ".microservices[0].variables.WIOTP_CLIENT_ID = \"g:$WIOTP_INSTALL_ORGID:$WIOTP_INSTALL_DEVICE_TYPE:$WIOTP_INSTALL_DEVICE_ID\" " <<< $configJson)
checkrc $?

configJson=$(jq ".microservices[0].variables.WIOTP_LOCAL_BROKER_PORT = \"2883\" " <<< $configJson)
checkrc $?
              
# Write the workload json definition file
echo "$configJson" > $CORE_IOT_HZN_INPUT_FILE

if [[ ! -z $CUSTOM_HZN_INPUT_FILE ]]; then
  if [[ -e $CUSTOM_HZN_INPUT_FILE ]]; then

    logIfVerbose "Merging custom hzn config input file ..."

    # Temporary files to store the arrays of both hznEdgeCoreIoTInput.json and the custom workload input json passed to "-f"
    # so that "jq -s '.=.|add'" command can concatenated the arrays
    CORE_IOT_ARRAY_FILE="/tmp/origArray.json"
    CUSTOM_ARRAY_FILE="/tmp/customArray.json"

    # Read the Json object from hznEdgeCoreIoTInput.json
    coreIoTJson=$(jq '.' $CORE_IOT_HZN_INPUT_FILE)
    checkrc $?
    # Read the Json object from the custom workload input json
    customJson=$(jq '.' $CUSTOM_HZN_INPUT_FILE)
    checkrc $?

    # Extract the "global" array from coreIoTJson
    coreIoTGlobalArray=$(jq -r '.global' <<< $coreIoTJson)
    checkrc $?
    # Extract the "global" array from customJson
    customGlobalArray=$(jq -r '.global' <<< $customJson)
    checkrc $?
    # Write the "global" array in the temporary file
    echo "$coreIoTGlobalArray" > $CORE_IOT_ARRAY_FILE
    echo "$customGlobalArray" > $CUSTOM_ARRAY_FILE
    # Merge both "global" arrays by reading them from the temporary files with "jq -s"
    mergedGlobalArray=$(jq -s '.=.|add' $CORE_IOT_ARRAY_FILE $CUSTOM_ARRAY_FILE)
    checkrc $?

    # Extract the "microservices" array from coreIoTJson
    coreIoTMicroservicesArray=$(jq -r '.microservices' <<< $coreIoTJson)
    checkrc $?
    # Extract the "microservices" array from customJson
    customMicroservicesArray=$(jq -r '.microservices' <<< $customJson)
    checkrc $?
    # Write the "microservices" array in the temporary file
    echo "$coreIoTMicroservicesArray" > $CORE_IOT_ARRAY_FILE
    echo "$customMicroservicesArray" > $CUSTOM_ARRAY_FILE
    # Merge both "microservices" arrays by reading them from the temporary files with "jq -s"
    mergedMicroservicesArray=$(jq -s '.=.|add' $CORE_IOT_ARRAY_FILE $CUSTOM_ARRAY_FILE)
    checkrc $?

    # Extract the "workloads" array from coreIoTJson
    coreIoTWorkloadsArray=$(jq -r '.workloads' <<< $coreIoTJson)
    checkrc $?
    # Extract the "workloads" array from customJson
    customWorkloadsArray=$(jq -r '.workloads' <<< $customJson)
    checkrc $?
    # Write the "workloads" array in the temporary file
    echo "$coreIoTWorkloadsArray" > $CORE_IOT_ARRAY_FILE
    echo "$customWorkloadsArray" > $CUSTOM_ARRAY_FILE
    # Merge both "workloads" arrays by reading them from the temporary files with "jq -s"
    mergedWorkloadsArray=$(jq -s '.=.|add' $CORE_IOT_ARRAY_FILE $CUSTOM_ARRAY_FILE)
    checkrc $?

    # Remove temporary files
    rm $CORE_IOT_ARRAY_FILE $CUSTOM_ARRAY_FILE

    # Write all merged arrays (global, microservices and workloads) and write them back to hznEdgeCoreIoTInput.json
    outputJson=$(jq ".global = $mergedGlobalArray " <<< $coreIoTJson)
    checkrc $?
    outputJson=$(jq ".microservices = $mergedMicroservicesArray " <<< $outputJson)
    checkrc $?
    outputJson=$(jq ".workloads = $mergedWorkloadsArray " <<< $outputJson)
    checkrc $?

    echo "$outputJson" > $CORE_IOT_HZN_INPUT_FILE
  else
    fatal "File $CUSTOM_HZN_INPUT_FILE not found."
  fi
fi


# Generate edge-mqttbroker certificates
mkdir -p ${VAR_DIR}/wiotp-edge/persist/

log "Generating Edge internal certificates ..." 
if [[ -z $WIOTP_INSTALL_EDGE_CN ]]; then
  wiotp_create_certificate -p $WIOTP_INSTALL_DEVICE_TOKEN $VERBOSE
  checkrc $?
else  
  wiotp_create_certificate -p $WIOTP_INSTALL_DEVICE_TOKEN  -cn $WIOTP_INSTALL_EDGE_CN $VERBOSE
  checkrc $?
fi

touch /tmp/hzn_register_vars.env
echo "export WIOTP_INSTALL_ORGID=$WIOTP_INSTALL_ORGID" > /tmp/hzn_register_vars.env
echo "export WIOTP_INSTALL_DEVICE_TYPE=$WIOTP_INSTALL_DEVICE_TYPE" >> /tmp/hzn_register_vars.env
echo "export WIOTP_INSTALL_DEVICE_ID=$WIOTP_INSTALL_DEVICE_ID" >> /tmp/hzn_register_vars.env
echo "export WIOTP_INSTALL_DEVICE_TOKEN=$WIOTP_INSTALL_DEVICE_TOKEN" >> /tmp/hzn_register_vars.env
echo "export VERBOSE=$VERBOSE" >> /tmp/hzn_register_vars.env

if [[ -z $SKIP_HORIZON_REGISTRATION ]]; then
  logIfVerbose "Waiting for Horizon service to restart ..."
  sleep 1

  wiotp_agent_register

else
  log "Horizon registration skipped. Edit /etc/wiotp-edge/hznEdgeCoreIoTInput.json to add specific workload/microservice variables, then run wiotp_agent_register (alternatively, run hzn register manually)."
fi

