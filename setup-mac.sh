#!/bin/bash
# One-time setup for the streaming Mac. Safe to run again; it skips what is already done.
#  1. Installs each page's dependencies exactly as pinned in its bun.lock.
#  2. Gives every wired Ethernet adapter a fixed 10.0.100.x address next to its normal one, so the
#     cameras (10.0.100.20 and up) are reachable on any network, with or without a router.
# Usage: ./setup-mac.sh
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)

if ! command -v bun >/dev/null; then
	echo "Bun is required. Install it from https://bun.sh, then run this again." >&2
	exit 1
fi

for app in cam overlays switcher; do
	echo "Installing $app dependencies"
	(cd "$ROOT/$app" && bun install --frozen-lockfile)
done

# Each service as "name|hardware port|device", skipping disabled ones
SERVICES=$(networksetup -listnetworkserviceorder | awk '
	/^\([0-9]+\) / { sub(/^\([0-9]+\) /, ""); name = $0; next }
	/^\(Hardware Port:/ && name != "" {
		port = $0; sub(/^\(Hardware Port: /, "", port); sub(/, Device:.*/, "", port)
		dev = $0; sub(/.*Device: /, "", dev); sub(/\)$/, "", dev)
		print name "|" port "|" dev; name = ""
	}')

# Devices that already have a camera address, and the addresses in use
HAVE=" " USED=" "
while IFS='|' read -r name _ dev; do
	[[ $name == "Camera Net ("* ]] || continue
	HAVE="$HAVE$dev "
	ip=$(networksetup -getinfo "$name" | awk -F': ' '/^IP address/ {print $2}')
	USED="$USED$ip "
done <<<"$SERVICES"

next_ip() {
	local n=2
	while [[ $USED == *" 10.0.100.$n "* ]]; do n=$((n + 1)); done
	echo "10.0.100.$n"
}

ADDED=0
while IFS='|' read -r name port dev; do
	# Wired adapters only: Wi-Fi, iPhone tethering, bridges, and VPNs never reach the camera switch
	[[ $dev == en* && $name != "Camera Net ("* ]] || continue
	[[ $port == Wi-Fi || $port == *iPhone* || $port == *Bluetooth* ]] && continue
	[[ $HAVE == *" $dev "* ]] && continue

	ip=$(next_ip)
	new="Camera Net ($name adapter)"
	networksetup -duplicatenetworkservice "$name" "$new"
	networksetup -setmanual "$new" "$ip" 255.255.255.0
	networksetup -setv6off "$new"
	echo "Added $ip on $port ($dev) as \"$new\""
	HAVE="$HAVE$dev " USED="$USED$ip "
	ADDED=1
done <<<"$SERVICES"

[[ $ADDED -eq 0 ]] && echo "Every Ethernet adapter already has a camera network address."
echo
echo "Done. Plug a USB Ethernet adapter in and run this again if it was not connected yet."
echo "Next: set up each camera with pi/push-setup.sh (see pi/README.md), then run ./competition.sh"
