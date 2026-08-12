#!/bin/sh
set -eu

IRSSI=${IRSSI:-irssi}
TIMEOUT=${IRSSI_TEST_TIMEOUT:-20}

for executable in "$IRSSI" script timeout perl; do
	if ! command -v "$executable" >/dev/null 2>&1; then
		printf '%s\n' "Incomplete HTTP header integration test requires '$executable'." >&2
		exit 1
	fi
done

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
home=$(mktemp -d "${TMPDIR:-/tmp}/autodl-irssi-http-header.XXXXXX")
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
ln -s "$repo/t/integration/http-incomplete-header-driver.pl" "$home/.irssi/scripts/http-incomplete-header-driver.pl"
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
perl "$repo/t/integration/http-incomplete-header-server.pl" "$ready" "$server_log" 3 2>"$server_error" &
server_pid=$!
IFS= read -r port <"$ready"
rm "$ready"
case $port in *[!0-9]*|'') printf '%s\n' "HTTP fixture returned invalid port '$port'." >&2; exit 1 ;; esac

window_log=$home/http-header-window.log
terminal_log=$home/http-header-terminal.log
commands=$home/commands
printf '/window log on "%s"\n' "$window_log" >"$commands"
cat >>"$commands" <<'COMMANDS'
/echo HTTPHEADER:IRSSI_STARTED_OFFLINE
/script load autodl-irssi.pl
/script load http-incomplete-header-driver.pl
COMMANDS

IRSSI_BIN=$(command -v "$IRSSI")
IRSSI_HOME=$home/.irssi
IRSSI_CONFIG=$home/.irssi/config
HOME=$home
TERM=xterm
AUTODL_HTTP_INCOMPLETE_HEADER_PORT=$port
export IRSSI_BIN IRSSI_HOME IRSSI_CONFIG HOME TERM AUTODL_HTTP_INCOMPLETE_HEADER_PORT

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
[ "$server_status" -eq 0 ] || { cat "$server_error" >&2; printf '%s\n' "HTTP fixture exited with status $server_status." >&2; exit 1; }
[ -s "$window_log" ] || { printf '%s\n' 'Irssi did not create its window log.' >&2; exit 1; }

assert_count() {
	actual=$(grep -F -c "$1" "$2" || true)
	[ "$actual" -eq "$3" ] || { printf '%s\n' "Expected '$1' $3 time(s), observed $actual." >&2; exit 1; }
}
assert_count 'HTTPHEADER:IRSSI_STARTED_OFFLINE' "$window_log" 1
assert_count 'HTTPHEADER:DRIVER_STARTED' "$window_log" 1
assert_count 'HTTPHEADER:IRSSI_RESPONSIVE' "$window_log" 1
assert_count 'HTTPHEADER:FINAL_CALLBACK:' "$window_log" 1
assert_count 'HTTPHEADER:FINAL_CALLBACK:1:Timed out! Error: Could not parse HTTP response header' "$window_log" 1
assert_count 'HTTPHEADER:SETTLE_COMPLETE' "$window_log" 1
assert_count 'REQUEST ' "$server_log" 3
assert_count 'PARTIAL_RESPONSE ' "$server_log" 3

if grep -Eiq 'segmentation fault|core dumped|uncaught exception|stale callback|forced termination|error in script|error loading script|assertion .* failed' "$window_log" "$terminal_log"; then
	printf '%s\n' 'Integration output contains a fatal diagnostic.' >&2
	exit 1
fi

printf '%s\n' 'Offline incomplete HTTP header characterization passed: 3 partial responses, 1 final callback.'
