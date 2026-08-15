#!/bin/sh
set -eu

IRSSI=${IRSSI:-irssi}
TIMEOUT=${IRSSI_TEST_TIMEOUT:-20}

for executable in "$IRSSI" script timeout; do
	if ! command -v "$executable" >/dev/null 2>&1; then
		printf '%s\n' "Tracker definition integration test requires '$executable'." >&2
		exit 1
	fi
done

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
home=$(mktemp -d "${TMPDIR:-/tmp}/autodl-irssi-tracker-defs.XXXXXX")
cleanup() {
	trap - EXIT HUP INT TERM
	rm -rf "$home"
}
trap cleanup EXIT HUP INT TERM

source_count=$(find "$repo/trackers" -maxdepth 1 -type f -name '*.tracker' | wc -l)
[ "$source_count" -eq 77 ] || {
	printf '%s\n' "Expected 77 imported tracker files, found $source_count." >&2
	exit 1
}

mkdir -p "$home/.irssi/scripts/AutodlIrssi/trackers" "$home/.autodl"
ln -s "$repo/autodl-irssi.pl" "$home/.irssi/scripts/autodl-irssi.pl"
ln -s "$repo/t/integration/tracker-definitions-driver.pl" "$home/.irssi/scripts/tracker-definitions-driver.pl"
for module in "$repo"/AutodlIrssi/*.pm; do
	ln -s "$module" "$home/.irssi/scripts/AutodlIrssi/$(basename "$module")"
done
cp "$repo"/trackers/*.tracker "$home/.irssi/scripts/AutodlIrssi/trackers/"
cp "$repo/t/fixtures/irssi/autodl.cfg" "$home/.autodl/autodl.cfg"
cp "$repo/t/fixtures/irssi/irssi.config" "$home/.irssi/config"

window_log=$home/tracker-definitions-window.log
terminal_log=$home/tracker-definitions-terminal.log
commands=$home/commands
printf '/window log on "%s"\n' "$window_log" >"$commands"
printf '%s\n' \
	'/echo TRACKERDEFS:IRSSI_STARTED_OFFLINE' \
	'/script load autodl-irssi.pl' \
	'/script load tracker-definitions-driver.pl' >>"$commands"

IRSSI_BIN=$(command -v "$IRSSI")
IRSSI_HOME=$home/.irssi
IRSSI_CONFIG=$home/.irssi/config
HOME=$home
TERM=xterm
AUTODL_TRACKER_SOURCE_METADATA=$repo/trackers/SOURCE.json
export IRSSI_BIN IRSSI_HOME IRSSI_CONFIG HOME TERM AUTODL_TRACKER_SOURCE_METADATA

set +e
timeout --kill-after=5 "$TIMEOUT" script --quiet --return --echo never \
	--command 'stty rows 50 cols 200 && exec "$IRSSI_BIN" --home="$IRSSI_HOME" --config="$IRSSI_CONFIG" --noconnect' \
	/dev/null <"$commands" >"$terminal_log" 2>&1
irssi_status=$?
set -e

cat "$window_log" 2>/dev/null || cat "$terminal_log"
[ "$irssi_status" -eq 0 ] || { printf '%s\n' "Irssi exited with status $irssi_status." >&2; exit 1; }
[ -s "$window_log" ] || { printf '%s\n' 'Irssi did not create its window log.' >&2; exit 1; }

assert_count() {
	actual=$(grep -F -c "$1" "$2" || true)
	[ "$actual" -eq "$3" ] || { printf '%s\n' "Expected '$1' $3 time(s), observed $actual." >&2; exit 1; }
}
assert_count 'TRACKERDEFS:IRSSI_STARTED_OFFLINE' "$window_log" 1
assert_count 'TRACKERDEFS:FILES:77' "$window_log" 1
assert_count 'TRACKERDEFS:PARSED:77' "$window_log" 1
assert_count 'TRACKERDEFS:UNIQUE_TYPES:77' "$window_log" 1
assert_count 'TRACKERDEFS:RELOADED:77' "$window_log" 1
assert_count 'TRACKERDEFS:PTP_ANNOUNCE_CONFIRMED' "$window_log" 1
assert_count 'TRACKERDEFS:NCORE_ANNOUNCE_CONFIRMED' "$window_log" 1
assert_count 'TRACKERDEFS:VALIDATION_CONFIRMED' "$window_log" 1
assert_count 'TRACKERDEFS:SETTLE_COMPLETE' "$window_log" 1

if grep -Eiq 'could not parse.*\.tracker|segmentation fault|core dumped|uncaught exception|forced termination|error in script|error loading script|assertion .* failed' "$window_log" "$terminal_log"; then
	printf '%s\n' 'Tracker definition output contains a fatal diagnostic.' >&2
	exit 1
fi

printf '%s\n' 'Offline tracker definition validation passed: 77 files parsed, unique, reloaded, and current PTP/nCore announces matched.'
