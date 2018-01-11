#!/bin/bash
# FOR INTERNAL USE ONLY (Test environments only)
# Script for adding a device into the gateway RLAC group
#
orgId=$1
apiKey=$2
apiToken=$3
gatewayType=$4
gatewayId=$5
deviceType=$6
deviceId=$7
testEnv=$8      #optional

if [[ -z $orgId ]] || [[ -z $apiKey ]] || [[ -z $apiToken ]] || [[ -z $gatewayType ]] || [[ -z $gatewayId ]] || [[ -z $deviceType ]] || [[ -z $deviceId ]]; then
cat <<EOF    

    Usage: $0 <OrgId> <apiKey> <apiToken> <gatewayType> <gatewayId> <deviceType> <deviceId> <testEnviroment>
    
    Arguments:
     OrgId
     apiKey 
     apiToken
     gatewayType
     gatewayId
     deviceType
     deviceId
     testEnvironment (optional) - if not provided will default to production: internetofthings.ibmcloud.com

EOF
    exit 1
fi

if [[ -z $testEnv ]] ; then
    domain="internetofthings.ibmcloud.com"
else
    domain="$testEnv.internetofthings.ibmcloud.com"    
fi
echo "Using domain $orgId.$domain ..." 
echo ""


gwId="$orgId%3A$gatewayType%3A$gatewayId"
echo ""
echo "Query gateway role g%3A$gwId"
curl -k -w "%{http_code}" -u "$apiKey:$apiToken" https://$orgId.$domain/api/v0002/authorization/devices/g%3A$gwId
echo ""

echo ""
echo "Query RLAC group"
curl -k -w "%{http_code}" -u "$apiKey:$apiToken" https://$orgId.$domain/api/v0002/bulk/devices/gw_def_res_grp%3A$gwId
echo ""

echo ""
echo "Add a device to the group"
curl -k -w "%{http_code}" -u "$apiKey:$apiToken" -X PUT -H "Content-Type: application/json" https://$orgId.$domain/api/v0002/bulk/devices/gw_def_res_grp%3A$gwId/add  -d "[{\"typeId\":\"$deviceType\",\"deviceId\": \"$deviceId\"}]"
echo ""

echo ""
echo "Query RLAC group again"
curl -k -w "%{http_code}" -u "$apiKey:$apiToken" https://$orgId.$domain/api/v0002/bulk/devices/gw_def_res_grp%3A$gwId
echo ""
echo ""
echo "Done."