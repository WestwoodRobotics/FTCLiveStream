#!/bin/bash
# Usage: sudo ./setup.sh <hostname> [static-ip/prefix] [gateway]
#   sudo ./setup.sh ftc-cam1
#   sudo ./setup.sh ftc-cam1 10.0.100.21/24 10.0.100.1
set -euo pipefail

if [[ $EUID -ne 0 || $# -lt 1 ]]; then
	echo "usage: sudo $0 <hostname> [static-ip/prefix] [gateway]" >&2
	exit 1
fi

HOSTNAME_NEW=$1
STATIC_IP=${2:-}
GATEWAY=${3:-}
HERE=$(cd "$(dirname "$0")" && pwd)
CONFIG=/boot/firmware/config.txt

apt-get update
apt-get install -y rpicam-apps python3

# PoE HATs feed 5V through the GPIO header, so the Pi cannot negotiate 5A and caps USB without this
for line in usb_max_current_enable=1 camera_auto_detect=1 dtoverlay=disable-wifi dtoverlay=disable-bt; do
	grep -qxF "$line" "$CONFIG" || echo "$line" >>"$CONFIG"
done

hostnamectl set-hostname "$HOSTNAME_NEW"

if [[ -n $STATIC_IP ]]; then
	CONNECTION=$(nmcli -t -f NAME,TYPE connection show | awk -F: '$2 ~ /ethernet/ {print $1; exit}')
	nmcli connection modify "$CONNECTION" ipv4.method manual ipv4.addresses "$STATIC_IP" \
		ipv4.gateway "$GATEWAY"
fi

id ftc-cam >/dev/null 2>&1 || useradd --system --no-create-home ftc-cam
install -d /opt/ftc-cam
install -m 755 "$HERE/ftc-cam-stream" "$HERE/ts-relay.py" /opt/ftc-cam/
[[ -f /etc/ftc-cam.env ]] || install -m 644 "$HERE/ftc-cam.env" /etc/ftc-cam.env
install -m 644 "$HERE/ftc-cam.service" /etc/systemd/system/ftc-cam.service
systemctl daemon-reload
systemctl enable ftc-cam

echo "Done. Reboot to apply the firmware settings; the camera starts on boot."
