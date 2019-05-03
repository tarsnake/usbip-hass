# Files Included:
1. usbipd.service (server/physical device)
2. usbip.service (client/HASS host)
3. udev rules file for *client* host -- maps USB device to `/dev/zwave` (add to `/etc/udev/rules.d/`)

# Setup:
See the original instructions here: https://community.home-assistant.io/t/rpi-as-z-wave-zigbee-over-ip-server-for-hass/23006
also see the notes below in each file.

# About the Manager Script on the client
This uses a manager script (basically an expanded init script) on the hass.io host machine to control the USB-IP device and manage the connections.

  1) Before connecting: Ping the host and see if it's available. If not, wait and retry using an exponential delay (1s, 2s, 4s, 16s, etc. to 256s). This gives time after, for example, a whole home power outage, where everything comes back at the same time, but you have to wait for the other server to come up first).
  2) After confirming the host is there, check if the USB-IP service is available. If it isn't, try to restart the service on the remote machine using SSH.  **FOR THIS TO WORK** you must have Public Key Authorization set up both directions on the 2 machines.
  3) After mounting the device, restart the homeassistant docker, if it's already running.
  
# About the server service file
The server's .service file actually includes a line to call the client (via SSH) and attempt to restart the client's service. It will continue on if it fails, but if it succeeds, this will cascade to re-mount the port on the client and restart Home Assistant.
  