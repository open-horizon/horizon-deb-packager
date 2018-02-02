#!/bin/bash

function checkrc {
	if [[ $1 -ne 0 ]]; then
		echo "Last command exited with rc $1, exiting."
		exit $1
	fi
}

if [[ -e /tmp/hzn_register_vars.env ]]; then
  source /tmp/hzn_register_vars.env
  echo "Registering Edge node ..."
  echo "hzn register -n \"g@$WIOTP_INSTALL_DEVICE_TYPE@$WIOTP_INSTALL_DEVICE_ID:$WIOTP_INSTALL_DEVICE_TOKEN\" -f /etc/wiotp-edge/hznEdgeCoreIoTInput.json $WIOTP_INSTALL_ORGID $WIOTP_INSTALL_DEVICE_TYPE $VERBOSE"
  hzn register -n "g@$WIOTP_INSTALL_DEVICE_TYPE@$WIOTP_INSTALL_DEVICE_ID:$WIOTP_INSTALL_DEVICE_TOKEN" -f /etc/wiotp-edge/hznEdgeCoreIoTInput.json $WIOTP_INSTALL_ORGID $WIOTP_INSTALL_DEVICE_TYPE $VERBOSE
  checkrc $?
  echo "Agent registration complete."
else
  echo "You need to run wiotp_agent_setup at least once before running wiotp_agent_register"
fi

