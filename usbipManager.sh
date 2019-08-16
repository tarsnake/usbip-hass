#!/bin/bash

###################################################################
#Script Name    : usbipManager
#Description    : USB IP Client Manger
#Args           : start / stop / restart / status
#Author         : shbatm
#Email          : support@shbatm.com
#Installation   : Install to a convenient location and update the
#                 path used in usbip.service file.
#                 Make sure you update the variables below
###################################################################

USBIP_SERVER_IP='192.168.1.12'
USB_SERIAL_ID='0658:0200'
REMOTE_USER='root'
REMOTE_SERVICE='usbipd.service'
HASS_DOCKER_NAME='homeassistant'


ATTEMPTS=8

USBIP="/usr/bin/usbip"
name=`basename $0`

SUDO=''
if (( $EUID != 0 )); then
    SUDO='sudo'
fi

# Backoff script from http://stackoverflow.com/a/8351489/580412
function with_backoff {
  local max_attempts=${ATTEMPTS-5}
  local timeout=${TIMEOUT-1}
  local attempt=0
  local exitCode=0

  while [[ $attempt < $max_attempts ]]
  do
    "$@" > /dev/null 2>&1
    exitCode=$?

    if [[ $exitCode == 0 ]]
    then
      break
    fi

    echo "Failure! Retrying in $timeout.." 1>&2
    sleep $timeout
    attempt=$(( attempt + 1 ))
    timeout=$(( timeout * 2 ))
  done

  if [[ $exitCode != 0 ]]
  then
    echo "Giving up! ($@)" 1>&2
  fi

  echo $exitCode
  return $exitCode
}

check_host() {
    # Check if the USB IP Host is online.
    reachable=$(with_backoff ping -c1 -W1 $USBIP_SERVER_IP)
    if [[ $reachable != 0 ]]
    then
      # TODO: Send WOL or other wakeup command to make sure host is on.
      echo "Error: Host unreachable at $USBIP_SERVER_IP." 1>&2
      exit 1
    fi
    if $SUDO $USBIP list -r $USBIP_SERVER_IP 2>&1 | grep -q 'could not connect'; then
      echo "Could not connect to USBIP Host Service at $USBIP_SERVER_IP." 1>&2

      # Attempt to restart remote service using ssh.
      # Note: Public Key Auth must be setup between the servers.
      echo "Attempting to restart $REMOTE_SERVICE on $USBIP_SERVER_IP..."
      ssh -t ${REMOTE_USER}@${USBIP_SERVER_IP} "sudo systemctl restart $REMOTE_SERVICE"

      # Script exits here because service start on remote host will re-call this script on start.
      exit 1
    else
        USB_BUS_ID=$($SUDO $USBIP list -r $USBIP_SERVER_IP | grep $USB_SERIAL_ID | cut -d: -f1)
        echo "Using USB Bus ID: $USB_BUS_ID"
        return 0
    fi
}

attach_host() {
    $SUDO $USBIP attach -r $USBIP_SERVER_IP -b $USB_BUS_ID
}

restart_hass() {
  if [[ "$(/usr/bin/docker ps -q -f name=$HASS_DOCKER_NAME)" ]]; then
    echo "Home Assistant is running. Restarting..."
    /usr/bin/docker restart $HASS_DOCKER_NAME
  fi
}

is_running() {
    $SUDO $USBIP port | grep '<Port in Use>' -q
}

case "$1" in
    start)
    if is_running; then
        echo "Port is active."
    else
        echo "Attempting connection"
        check_host
        attach_host
        sleep 1
        if ! is_running; then
            echo "Unable to start $name. Unspecified error." 1>&2
            exit 1
        fi
        echo "Successfully started $name."
        restart_hass
    fi
    ;;
    stop)
    if is_running; then
        echo -n "Stopping $name..."
        $SUDO $USBIP detach --port=$($USBIP port | grep '<Port in Use>' | sed -E 's/^Port ([0-9][0-9]).*/\1/') > /dev/null 2>&1
        for i in 1 2 3 4 5 6 7 8 9 10
        # for i in `seq 10`
        do
            if ! is_running; then
                break
            fi
            echo -n "."
            sleep 1
        done
        echo

        if is_running; then
            echo "Not stopped; may still be shutting down or shutdown may have failed."
            exit 1
        else
            echo "Stopped."
        fi
    else
        echo "Not running."
    fi
    ;;
    restart)
    $0 stop
    if is_running; then
        echo "Unable to stop, will not attempt to start"
        exit 1
    fi
    $0 start
    ;;
    status)
    if is_running; then
        echo "Running"
    else
        echo "Stopped"
        exit 1
    fi
    ;;
    *)
    echo "Usage: $0 {start|stop|restart|status}"
    exit 1
    ;;
esac

exit 0