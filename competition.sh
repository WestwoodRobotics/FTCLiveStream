#!/bin/bash
# Starts the cam, overlay, and switcher pages, checks everything the stream depends on, prints the
# URLs for OBS, then keeps watching the cameras and FTC Live and beeps when one drops.
# Usage: ./competition.sh [ftclive-host[:port]] [event-code] [region] [level]
#   ./competition.sh 192.168.1.101 ustxcmp Texas Championship
# Ctrl+C stops the pages this script started. Run ./setup-mac.sh once on a new Mac first.
# Different camera names or addresses: CAMERAS="cam1=10.0.100.30 cam2=10.0.100.31" ./competition.sh

ROOT=$(cd "$(dirname "$0")" && pwd)
FTCLIVE=${1:-}
CODE=${2:-}
REGION=${3:-}
LEVEL=${4:-}
# Fixed addresses set by pi/push-setup.sh; this Mac reaches them through its own 10.0.100.x address
CAMERAS=${CAMERAS:-"live0=10.0.100.20 live1=10.0.100.21"}
LOGS="${TMPDIR:-/tmp}/ftclivestream"
PIDS=""
FAILED=0
mkdir -p "$LOGS"

ok() { printf '  \033[32mOK\033[0m    %s\n' "$*"; }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; FAILED=1; }
note() { printf '  \033[33mNOTE\033[0m  %s\n' "$*"; }
encode() { python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"; }

# Bytes a camera sends in two seconds; the stream never ends, so curl always stops on the timeout
stream_bytes() { curl -s --max-time 2 -o /dev/null -w '%{size_download}' "http://$1:8000/live.ts"; }
ftclive_up() { [[ $(curl -s --max-time 3 -o /dev/null -w '%{http_code}' "http://$FTCLIVE/") != 000 ]]; }

start_page() { # app port [extra vite args]
	local app=$1 port=$2
	shift 2
	curl -s --max-time 1 -o /dev/null "http://localhost:$port/" && return
	[[ -d $ROOT/$app/node_modules ]] || return
	(cd "$ROOT/$app" && exec bun run dev "$@") >"$LOGS/$app.log" 2>&1 &
	PIDS="$PIDS $!"
}

stop_pages() {
	# bun runs vite as a child process, so stop the children too
	for pid in $PIDS; do
		pkill -TERM -P "$pid" 2>/dev/null
		kill "$pid" 2>/dev/null
	done
	exit 0
}
trap stop_pages INT TERM

echo "Starting pages (logs in $LOGS)"
start_page cam 23456
start_page overlays 5173 --port 5173 --strictPort
start_page switcher 17113

for _ in $(seq 1 40); do
	curl -s --max-time 1 -o /dev/null http://localhost:23456/ &&
		curl -s --max-time 1 -o /dev/null http://localhost:5173/ &&
		curl -s --max-time 1 -o /dev/null http://localhost:17113/ && break
	sleep 0.5
done

echo
echo "Pages"
for page in cam=23456 overlays=5173 switcher=17113; do
	if curl -s --max-time 2 -o /dev/null "http://localhost:${page#*=}/"; then
		ok "${page%=*} page on port ${page#*=}"
	else
		if [[ -d $ROOT/${page%=*}/node_modules ]]; then
			bad "${page%=*} page is not running. See $LOGS/${page%=*}.log"
		else
			bad "${page%=*} page has no dependencies installed. Run ./setup-mac.sh"
		fi
	fi
done

echo
echo "Internet"
DEFAULT_IF=$(route -n get default 2>/dev/null | awk '/interface:/ {print $2}')
WIFI_IF=$(networksetup -listallhardwareports | awk '/Hardware Port: Wi-Fi/ {getline; print $2}')
if [[ $DEFAULT_IF == "$WIFI_IF" ]]; then
	ok "internet goes through Wi-Fi ($WIFI_IF)"
else
	bad "internet goes through ${DEFAULT_IF:-nothing}, not Wi-Fi. Join the school Wi-Fi and keep Wi-Fi first in the service order"
fi
if [[ $(curl -s --max-time 5 -o /dev/null -w '%{http_code}' https://www.youtube.com/) == [23]* ]]; then
	ok "YouTube is reachable"
else
	bad "YouTube is not reachable. The Wi-Fi may need a sign-in page; open any site in Brave"
fi

echo
echo "Cameras"
CAM_IF=$(ifconfig | awk '/^[a-z]/ {iface=$1} /inet 10\.0\.100\./ {sub(":", "", iface); print iface; exit}')
if [[ -n $CAM_IF ]]; then
	ok "camera network address on $CAM_IF"
else
	bad "no Ethernet adapter has a 10.0.100.x address. Plug the Mac into the PoE switch, or run ./setup-mac.sh on a new Mac"
fi
for cam in $CAMERAS; do
	name=${cam%=*} addr=${cam#*=}
	bytes=$(stream_bytes "$addr")
	if [[ ${bytes:-0} -gt 0 ]]; then
		ok "$name streaming at $addr ($((bytes * 8 / 2 / 1000000)) Mbps)"
	else
		bad "$name is not streaming at $addr. Check its PoE light and cable"
	fi
done

echo
echo "FTC Live"
if [[ -z $FTCLIVE || -z $CODE ]]; then
	note "skipped. Run ./competition.sh <ftclive-host[:port]> <event-code> to check it and fill in the overlay URL"
elif ftclive_up; then
	ok "FTC Live answers at $FTCLIVE"
else
	bad "FTC Live does not answer at $FTCLIVE. Check the host from the scoring computer"
fi

echo
note "OBS needs Local Network access to reach FTC Live: System Settings > Privacy & Security > Local Network"
[[ $FAILED -eq 0 ]] && echo "All checks passed." || printf '\a\nSome checks failed. Fix them before the first match.\n'

echo
echo "URLs for OBS browser sources"
CAM_PAGES=""
for cam in $CAMERAS; do
	page="http://localhost:23456/?url=http://${cam#*=}:8000/live.ts"
	CAM_PAGES="$CAM_PAGES $page"
	printf '  %-9s %s\n' "${cam%=*}:" "$page"
done
if [[ -n $FTCLIVE && -n $CODE ]]; then
	echo "  overlays: http://localhost:5173/?host=$FTCLIVE&code=$CODE&region=$(encode "$REGION")&level=$(encode "$LEVEL")"
	# The switcher cuts between the first two cameras
	set -- $CAM_PAGES
	echo "  switcher: http://localhost:17113/?obs=true&ws=$(encode "ws://$FTCLIVE/stream/display/command/?code=$CODE")&field1=$(encode "${1:-}")&field2=$(encode "${2:-}")"
fi

echo
echo "Watching cameras and FTC Live. Leave this window open; Ctrl+C stops the pages."
LAST=""
while true; do
	STATUS=""
	for cam in $CAMERAS; do
		bytes=$(stream_bytes "${cam#*=}")
		[[ ${bytes:-0} -gt 0 ]] && STATUS="$STATUS ${cam%=*}:up" || STATUS="$STATUS ${cam%=*}:DOWN"
	done
	if [[ -n $FTCLIVE ]]; then
		ftclive_up && STATUS="$STATUS ftclive:up" || STATUS="$STATUS ftclive:DOWN"
	fi
	if [[ $STATUS != "$LAST" ]]; then
		[[ $STATUS == *DOWN* ]] && printf '\a'
		echo "  $(date +%H:%M:%S)$STATUS"
		LAST=$STATUS
	fi
	# Waiting on a background sleep lets Ctrl+C stop the script right away
	sleep 10 &
	wait $!
done
