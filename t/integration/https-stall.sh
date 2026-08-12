#!/bin/sh
set -eu

IRSSI=${IRSSI:-irssi}
TIMEOUT=${IRSSI_TEST_TIMEOUT:-20}
STALL_MS=${HTTPS_STALL_MS:-2500}

for executable in "$IRSSI" script timeout perl; do
	if ! command -v "$executable" >/dev/null 2>&1; then
		printf '%s\n' "HTTPS stall integration test requires '$executable'." >&2
		exit 1
	fi
done
perl -MIO::Socket::SSL -MNet::SSLeay -e 1

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
home=$(mktemp -d "${TMPDIR:-/tmp}/autodl-irssi-https-stall.XXXXXX")
server_pid=
cleanup() {
	trap - EXIT HUP INT TERM
	if [ -n "$server_pid" ] && kill -0 "$server_pid" 2>/dev/null; then
		kill "$server_pid" 2>/dev/null || true
	fi
	if [ -n "$server_pid" ]; then
		wait "$server_pid" 2>/dev/null || true
	fi
	rm -rf "$home"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$home/.irssi/scripts/AutodlIrssi/trackers" "$home/.autodl"
ln -s "$repo/autodl-irssi.pl" "$home/.irssi/scripts/autodl-irssi.pl"
ln -s "$repo/t/integration/https-stall-driver.pl" "$home/.irssi/scripts/https-stall-driver.pl"
for module in "$repo"/AutodlIrssi/*.pm; do
	ln -s "$module" "$home/.irssi/scripts/AutodlIrssi/$(basename "$module")"
done
cp "$repo/t/fixtures/irssi/minimal.tracker" "$home/.irssi/scripts/AutodlIrssi/trackers/"
cp "$repo/t/fixtures/irssi/autodl.cfg" "$home/.autodl/autodl.cfg"
cp "$repo/t/fixtures/irssi/irssi.config" "$home/.irssi/config"

ready=$home/server.ready
server_log=$home/server.events
server_error=$home/server.error
mkfifo "$ready"
perl "$repo/t/integration/https-stall-server.pl" \
	"$ready" "$server_log" \
	"$repo/t/fixtures/tls/localhost-cert.pem" \
	"$repo/t/fixtures/tls/localhost-key.pem" \
	"$STALL_MS" 2>"$server_error" &
server_pid=$!
IFS= read -r port <"$ready"
rm "$ready"
case $port in *[!0-9]*|'') printf '%s\n' "TLS fixture returned invalid port '$port'." >&2; exit 1 ;; esac

window_log=$home/https-stall-window.log
terminal_log=$home/https-stall-terminal.log
commands=$home/commands
printf '/window log on "%s"\n' "$window_log" >"$commands"
cat >>"$commands" <<'COMMANDS'
/echo HTTPSSTALL:IRSSI_STARTED_OFFLINE
/script load autodl-irssi.pl
/script load https-stall-driver.pl
COMMANDS

IRSSI_BIN=$(command -v "$IRSSI")
IRSSI_HOME=$home/.irssi
IRSSI_CONFIG=$home/.irssi/config
HOME=$home
TERM=xterm
AUTODL_HTTPS_STALL_PORT=$port
export IRSSI_BIN IRSSI_HOME IRSSI_CONFIG HOME TERM AUTODL_HTTPS_STALL_PORT

set +e
timeout --kill-after=5 "$TIMEOUT" script --quiet --return --echo never \
	--command 'stty rows 50 cols 200 && exec "$IRSSI_BIN" --home="$IRSSI_HOME" --config="$IRSSI_CONFIG" --noconnect' \
	/dev/null <"$commands" >"$terminal_log" 2>&1
irssi_status=$?
set -e

set +e
wait "$server_pid"
server_status=$?
set -e
server_pid=

cat "$window_log" 2>/dev/null || cat "$terminal_log"
cat "$server_log" 2>/dev/null || true
[ "$irssi_status" -eq 0 ] || { printf '%s\n' "Irssi exited with status $irssi_status." >&2; exit 1; }
[ "$server_status" -eq 0 ] || { cat "$server_error" >&2; printf '%s\n' "TLS fixture exited with status $server_status." >&2; exit 1; }
[ -s "$window_log" ] || { printf '%s\n' 'Irssi did not create its window log.' >&2; exit 1; }

assert_count() {
	actual=$(grep -F -c "$1" "$2" || true)
	[ "$actual" -eq "$3" ] || { printf '%s\n' "Expected '$1' $3 time(s), observed $actual." >&2; exit 1; }
}
assert_count 'HTTPSSTALL:IRSSI_STARTED_OFFLINE' "$window_log" 1
assert_count 'HTTPSSTALL:DRIVER_STARTED' "$window_log" 1
assert_count 'HTTPSSTALL:REQUEST_SENT' "$window_log" 1
assert_count 'HTTPSSTALL:IRSSI_TIMER_FIRED' "$window_log" 1
assert_count 'HTTPSSTALL:FINAL_CALLBACK:1:SUCCESS:HTTP/1.1 200 OK:4' "$window_log" 1
assert_count 'HTTPSSTALL:SETTLE_COMPLETE' "$window_log" 1
assert_count 'TLS_HANDSHAKE_COMPLETE ' "$server_log" 1
assert_count 'REQUEST_RECEIVED GET /issue-190.torrent HTTP/1.1' "$server_log" 1
assert_count "STALL_BEGIN $STALL_MS" "$server_log" 1
assert_count 'STALL_END' "$server_log" 1
assert_count 'RESPONSE_SENT HTTP/1.1 200 OK' "$server_log" 1

callback_line=$(grep -n -F 'HTTPSSTALL:FINAL_CALLBACK:1:' "$window_log" | cut -d: -f1)
timer_line=$(grep -n -F 'HTTPSSTALL:IRSSI_TIMER_FIRED' "$window_log" | cut -d: -f1)
if [ "$callback_line" -lt "$timer_line" ]; then
	observation='callback-before-timer (event loop delayed during TLS read)'
else
	observation='timer-before-callback (event loop remained responsive)'
fi

if grep -Eiq 'segmentation fault|core dumped|uncaught exception|stale callback|forced termination|error in script|error loading script|assertion .* failed' "$window_log" "$terminal_log"; then
	printf '%s\n' 'Integration output contains a fatal diagnostic.' >&2
	exit 1
fi

printf '%s\n' "Offline HTTPS stall characterization passed: $observation."
