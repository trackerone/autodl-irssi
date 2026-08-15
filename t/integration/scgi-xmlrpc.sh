#!/bin/sh
set -eu

IRSSI=${IRSSI:-irssi}
TIMEOUT=${IRSSI_TEST_TIMEOUT:-25}

for executable in "$IRSSI" script timeout perl; do
	if ! command -v "$executable" >/dev/null 2>&1; then
		printf '%s\n' "SCGI/XML-RPC integration test requires '$executable'." >&2
		exit 1
	fi
done

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fixture_home=$(mktemp -d "${TMPDIR:-/tmp}/autodl-irssi-scgi-xmlrpc.XXXXXX")
tcp_pid=
unix_pid=
cleanup() {
	trap - EXIT HUP INT TERM
	for pid in "$tcp_pid" "$unix_pid"; do
		if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
			kill "$pid" 2>/dev/null || true
		fi
	done
	for pid in "$tcp_pid" "$unix_pid"; do
		if [ -n "$pid" ]; then
			wait "$pid" 2>/dev/null || true
		fi
	done
	rm -rf "$fixture_home"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$fixture_home/.irssi/scripts/AutodlIrssi/trackers" "$fixture_home/.autodl"
ln -s "$repo/autodl-irssi.pl" "$fixture_home/.irssi/scripts/autodl-irssi.pl"
ln -s "$repo/t/integration/scgi-xmlrpc-driver.pl" "$fixture_home/.irssi/scripts/scgi-xmlrpc-driver.pl"
for module in "$repo"/AutodlIrssi/*.pm; do
	ln -s "$module" "$fixture_home/.irssi/scripts/AutodlIrssi/$(basename "$module")"
done
cp "$repo/t/fixtures/irssi/minimal.tracker" "$fixture_home/.irssi/scripts/AutodlIrssi/trackers/"
cp "$repo/t/fixtures/irssi/autodl.cfg" "$fixture_home/.autodl/autodl.cfg"
cp "$repo/t/fixtures/irssi/irssi.config" "$fixture_home/.irssi/config"

tcp_ready=$fixture_home/tcp.ready
tcp_log=$fixture_home/tcp.requests
tcp_error=$fixture_home/tcp.error
mkfifo "$tcp_ready"
perl "$repo/t/integration/scgi-xmlrpc-server.pl" tcp "$tcp_ready" - "$tcp_log" success 2>"$tcp_error" &
tcp_pid=$!
IFS= read -r port <"$tcp_ready"
rm "$tcp_ready"
case $port in *[!0-9]*|'') printf '%s\n' "Fixture returned invalid port '$port'." >&2; exit 1 ;; esac

socket_path=$fixture_home/rtorrent.sock
unix_ready=$fixture_home/unix.ready
unix_log=$fixture_home/unix.requests
unix_error=$fixture_home/unix.error
mkfifo "$unix_ready"
perl "$repo/t/integration/scgi-xmlrpc-server.pl" unix "$unix_ready" "$socket_path" "$unix_log" fault 2>"$unix_error" &
unix_pid=$!
IFS= read -r reported_socket <"$unix_ready"
rm "$unix_ready"
[ "$reported_socket" = "$socket_path" ] || { printf '%s\n' "Fixture returned unexpected socket '$reported_socket'." >&2; exit 1; }

window_log=$fixture_home/scgi-xmlrpc-window.log
terminal_log=$fixture_home/scgi-xmlrpc-terminal.log
commands_file=$fixture_home/commands
printf '/window log on "%s"\n' "$window_log" >"$commands_file"
cat >>"$commands_file" <<'COMMANDS'
/echo SCGIXMLRPC:IRSSI_STARTED_OFFLINE
/script load autodl-irssi.pl
/script load scgi-xmlrpc-driver.pl
COMMANDS

irssi_bin=$(command -v "$IRSSI")
set +e
env \
	HOME="$fixture_home" \
	IRSSI_BIN="$irssi_bin" \
	IRSSI_HOME="$fixture_home/.irssi" \
	IRSSI_CONFIG="$fixture_home/.irssi/config" \
	TERM=xterm \
	AUTODL_SCGI_PORT="$port" \
	AUTODL_SCGI_SOCKET="$socket_path" \
	timeout --kill-after=5 "$TIMEOUT" script --quiet --return --echo never \
		--command 'stty rows 50 cols 200 && exec "$IRSSI_BIN" --home="$IRSSI_HOME" --config="$IRSSI_CONFIG" --noconnect' \
		/dev/null <"$commands_file" >"$terminal_log" 2>&1
irssi_status=$?
set -e

set +e
wait "$tcp_pid"
tcp_status=$?
tcp_pid=
wait "$unix_pid"
unix_status=$?
unix_pid=
set -e

cat "$window_log" 2>/dev/null || cat "$terminal_log"
cat "$tcp_log" 2>/dev/null || true
cat "$unix_log" 2>/dev/null || true
[ "$irssi_status" -eq 0 ] || { printf '%s\n' "Irssi exited with status $irssi_status." >&2; exit 1; }
[ "$tcp_status" -eq 0 ] || { cat "$tcp_error" >&2; printf '%s\n' "TCP SCGI fixture exited with status $tcp_status." >&2; exit 1; }
[ "$unix_status" -eq 0 ] || { cat "$unix_error" >&2; printf '%s\n' "Unix SCGI fixture exited with status $unix_status." >&2; exit 1; }
[ -s "$window_log" ] || { printf '%s\n' 'Irssi did not create its window log.' >&2; exit 1; }

assert_count() {
	actual=$(grep -F -c "$1" "$2" || true)
	[ "$actual" -eq "$3" ] || { printf '%s\n' "Expected '$1' $3 time(s), observed $actual." >&2; exit 1; }
}
assert_count 'SCGIXMLRPC:IRSSI_STARTED_OFFLINE' "$window_log" 1
assert_count 'SCGIXMLRPC:DRIVER_STARTED' "$window_log" 1
assert_count 'SCGIXMLRPC:IRSSI_RESPONSIVE' "$window_log" 1
assert_count 'SCGIXMLRPC:TCP_CALLBACK:1::tcp-ok' "$window_log" 1
assert_count 'SCGIXMLRPC:UNIX_CALLBACK:2:XML-RPC call failed (17): fixture fault:' "$window_log" 1
assert_count 'SCGIXMLRPC:SETTLE_COMPLETE' "$window_log" 1
assert_count 'TRANSPORT tcp' "$tcp_log" 1
assert_count 'METHOD load.start' "$tcp_log" 1
assert_count 'PARAMETERS 3' "$tcp_log" 1
assert_count 'REQUEST_VALIDATED' "$tcp_log" 1
assert_count 'RESPONSE success' "$tcp_log" 1
assert_count 'TRANSPORT unix' "$unix_log" 1
assert_count 'METHOD load.start' "$unix_log" 1
assert_count 'PARAMETERS 3' "$unix_log" 1
assert_count 'REQUEST_VALIDATED' "$unix_log" 1
assert_count 'RESPONSE fault' "$unix_log" 1

if grep -Eiq 'SCGIXMLRPC:FAIL|segmentation fault|core dumped|uncaught exception|forced termination|error in script|error loading script|assertion .* failed' "$window_log" "$terminal_log"; then
	printf '%s\n' 'SCGI/XML-RPC integration output contains a fatal diagnostic.' >&2
	exit 1
fi

printf '%s\n' "Offline SCGI/XML-RPC characterization passed: TCP $port, Unix socket, success and fault callbacks."
