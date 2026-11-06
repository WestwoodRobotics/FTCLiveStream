#!/bin/bash
# Runs setup.sh on a camera Pi from this computer, reboots it, and waits for its stream.
# Run it while the Pi still has internet, since setup.sh installs packages first.
# Usage: ./push-setup.sh [user@]<current-address> <hostname> <static-ip/prefix>
#   ./push-setup.sh pvp@live0.local live0 10.0.100.20/24
#   ./push-setup.sh pvp@10.0.100.20 live0 10.0.100.20/24    (rerun after it has its fixed address)
# The user is the one created when flashing the card; it defaults to pi.
set -euo pipefail

if [[ $# -ne 3 ]]; then
	echo "usage: $0 [user@]<current-address> <hostname> <static-ip/prefix>" >&2
	exit 1
fi

if [[ $1 == *@* ]]; then
	TARGET=$1
else
	TARGET="${PI_USER:-pi}@$1"
fi
ADDR=${TARGET#*@}
NAME=$2
STATIC_IP=$3
NEW_ADDR=${STATIC_IP%/*}
HERE=$(cd "$(dirname "$0")" && pwd)
SOCKET=$(mktemp -u "${TMPDIR:-/tmp}/ftc-cam-ssh.XXXXXX")

# This computer needs an address on the new subnet, or the Pi is unreachable after the reboot
if ! ifconfig | grep -q "inet ${NEW_ADDR%.*}\."; then
	echo "No address on ${NEW_ADDR%.*}.0/24 here. Run ./setup-mac.sh from the repo folder first." >&2
	exit 1
fi

# One login is shared by every step below, so the SSH password is asked once
ssh -fNM -S "$SOCKET" -o ControlPersist=300 -o StrictHostKeyChecking=accept-new "$TARGET"
trap 'ssh -S "$SOCKET" -O exit "$TARGET" 2>/dev/null || true' EXIT

ssh -S "$SOCKET" "$TARGET" 'rm -rf /tmp/ftc-cam-setup'
scp -q -o ControlPath="$SOCKET" -r "$HERE" "$TARGET:/tmp/ftc-cam-setup"
# The reboot is scheduled rather than run, so this session ends cleanly and reports setup's result
ssh -S "$SOCKET" -t "$TARGET" "sudo sh -c 'bash /tmp/ftc-cam-setup/setup.sh $NAME $STATIC_IP && systemd-run --on-active=3 systemctl reboot'"

echo "$NAME is rebooting. Waiting for it at $NEW_ADDR..."
# The stream never ends, so curl always times out; count the bytes it received instead
BYTES=0
for _ in $(seq 1 60); do
	BYTES=$(curl -s --max-time 2 -o /dev/null -w '%{size_download}' http://"$NEW_ADDR":8000/live.ts || true)
	if [[ ${BYTES:-0} -gt 0 ]]; then
		break
	fi
	sleep 1
done

if [[ ${BYTES:-0} -gt 0 ]]; then
	echo "OK: $NAME is streaming at http://$NEW_ADDR:8000/live.ts"
else
	echo "$NAME did not come back at $NEW_ADDR within 3 minutes." >&2
	echo "If setup failed before the reboot, it is still at $ADDR." >&2
	exit 1
fi
