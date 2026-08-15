#!/bin/sh
set -eu

IRSSI=${IRSSI:-irssi}
TIMEOUT=${IRSSI_TEST_TIMEOUT:-20}

for executable in "$IRSSI" script timeout perl zip unzip sha256sum cmp; do
	if ! command -v "$executable" >/dev/null 2>&1; then
		printf '%s\n' "Tracker update integration test requires '$executable'." >&2
		exit 1
	fi
done

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
version=$(sed -n '1p' "$repo/trackers/VERSION")
tracker_count=$(find "$repo/trackers" -maxdepth 1 -type f -name '*.tracker' | wc -l)
home=$(mktemp -d "${TMPDIR:-/tmp}/autodl-irssi-tracker-update.XXXXXX")
cleanup() {
	trap - EXIT HUP INT TERM
	rm -rf "$home"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$home/.irssi/scripts/AutodlIrssi/trackers" "$home/.autodl"
release_dir=$home/release
"$repo/scripts/build-tracker-release.sh" "$release_dir"
ln -s "$repo/autodl-irssi.pl" "$home/.irssi/scripts/autodl-irssi.pl"
ln -s "$repo/t/integration/tracker-update-install-driver.pl" "$home/.irssi/scripts/tracker-update-install-driver.pl"
for module in "$repo"/AutodlIrssi/*.pm; do
	ln -s "$module" "$home/.irssi/scripts/AutodlIrssi/$(basename "$module")"
done
cp "$repo/t/fixtures/irssi/minimal.tracker" "$home/.irssi/scripts/AutodlIrssi/trackers/current.tracker"
cp "$repo/t/fixtures/tracker-update/obsolete.tracker" "$home/.irssi/scripts/AutodlIrssi/trackers/obsolete.tracker"
cp "$repo/t/fixtures/irssi/autodl.cfg" "$home/.autodl/autodl.cfg"
cp "$repo/t/fixtures/irssi/irssi.config" "$home/.irssi/config"

window_log=$home/tracker-update-window.log
terminal_log=$home/tracker-update-terminal.log
commands=$home/commands
printf '/window log on "%s"\n' "$window_log" >"$commands"
printf '%s\n' \
	'/echo TRACKERUPDATE:IRSSI_STARTED_OFFLINE' \
	'/script load autodl-irssi.pl' \
	'/script load tracker-update-install-driver.pl' >>"$commands"

IRSSI_BIN=$(command -v "$IRSSI")
IRSSI_HOME=$home/.irssi
IRSSI_CONFIG=$home/.irssi/config
HOME=$home
TERM=xterm
AUTODL_TRACKER_UPDATE_FIXTURE_DIR=$repo/t/fixtures/tracker-update
AUTODL_TRACKER_RELEASE_DIR=$release_dir
AUTODL_TRACKER_SOURCE_DIR=$repo/trackers
export IRSSI_BIN IRSSI_HOME IRSSI_CONFIG HOME TERM AUTODL_TRACKER_UPDATE_FIXTURE_DIR \
	AUTODL_TRACKER_RELEASE_DIR AUTODL_TRACKER_SOURCE_DIR

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
assert_count 'TRACKERUPDATE:IRSSI_STARTED_OFFLINE' "$window_log" 1
assert_count 'TRACKERUPDATE:DRIVER_STARTED' "$window_log" 1
assert_count 'TRACKERUPDATE:SOURCE:trackerone/autodl-irssi' "$window_log" 1
assert_count "TRACKERUPDATE:VERSION:$version" "$window_log" 1
assert_count "TRACKERUPDATE:ASSET:autodl-trackers-v$version.zip" "$window_log" 1
assert_count "TRACKERUPDATE:CHECKSUM_ASSET:autodl-trackers-v$version.zip.sha256" "$window_log" 1
assert_count 'TRACKERUPDATE:MISSING_ASSET_REJECTED' "$window_log" 1
assert_count 'TRACKERUPDATE:MISSING_CHECKSUM_REJECTED' "$window_log" 1
assert_count 'TRACKERUPDATE:CHECKSUM_MISMATCH_REJECTED' "$window_log" 1
assert_count 'TRACKERUPDATE:FINAL_CALLBACK:1:' "$window_log" 1
assert_count 'TRACKERUPDATE:ROLLBACK_CONFIRMED' "$window_log" 1
assert_count 'TRACKERUPDATE:ARCHIVE_VALIDATION_REJECTED' "$window_log" 1
assert_count 'TRACKERUPDATE:REQUEST_SEQUENCE_CONFIRMED' "$window_log" 1
assert_count "TRACKERUPDATE:FILES:$tracker_count" "$window_log" 1
assert_count "TRACKERUPDATE:LOADED_TYPES:$tracker_count" "$window_log" 1
assert_count 'TRACKERUPDATE:INSTALL_CONFIRMED' "$window_log" 1
assert_count 'TRACKERUPDATE:SETTLE_COMPLETE' "$window_log" 1

if grep -Eiq 'segmentation fault|core dumped|uncaught exception|forced termination|error in script|error loading script|assertion .* failed' "$window_log" "$terminal_log"; then
	printf '%s\n' 'Integration output contains a fatal diagnostic.' >&2
	exit 1
fi

printf '%s\n' "Offline tracker release/update flow passed: checksum verified, $tracker_count installed, rollback preserved the prior installation."
