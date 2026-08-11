#!/bin/sh
set -eu

IRSSI=${IRSSI:-irssi}
TIMEOUT=${IRSSI_TEST_TIMEOUT:-30}

if ! command -v "$IRSSI" >/dev/null 2>&1; then
	printf '%s\n' "Irssi integration test requires the 'irssi' executable (Ubuntu package: irssi)." >&2
	exit 1
fi

# These options are provided by Ubuntu 24.04's packaged Irssi.  Check the
# executable itself so a package/CLI mismatch fails before the test is run.
help=$($IRSSI --help 2>&1)
for option in --config --home --no-connect --no-autorun --dummy; do
	case "$help" in
		*"$option"*) ;;
		*) printf '%s\n' "Installed Irssi does not support required option: $option" >&2; exit 1 ;;
	esac
done

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=${TMPDIR:-/tmp}
home=$(mktemp -d "$tmp/autodl-irssi-lifecycle.XXXXXX")
output=$home/irssi-output.log
trap 'rm -rf "$home"' EXIT HUP INT TERM

mkdir -p "$home/.irssi/scripts/AutodlIrssi/trackers" "$home/.autodl"
ln -s "$repo/autodl-irssi.pl" "$home/.irssi/scripts/autodl-irssi.pl"
for module in "$repo"/AutodlIrssi/*.pm; do
	ln -s "$module" "$home/.irssi/scripts/AutodlIrssi/$(basename "$module")"
done
cp "$repo/t/fixtures/irssi/minimal.tracker" "$home/.irssi/scripts/AutodlIrssi/trackers/"
cp "$repo/t/fixtures/irssi/autodl.cfg" "$home/.autodl/autodl.cfg"
cp "$repo/t/fixtures/irssi/irssi.config" "$home/.irssi/config"

set +e
HOME=$home TERM=dumb timeout --foreground "$TIMEOUT" "$IRSSI" \
	--home="$home/.irssi" --config="$home/.irssi/config" \
	--no-connect --no-autorun --dummy >"$output" 2>&1 <<'COMMANDS'
/echo HARNESS:IRSSI_STARTED_OFFLINE
/script load autodl-irssi.pl
/echo HARNESS:FIRST_LOAD_COMPLETE
/script unload autodl-irssi
/echo HARNESS:FIRST_UNLOAD_COMPLETE
/script load autodl-irssi.pl
/echo HARNESS:SECOND_LOAD_COMPLETE
/script unload autodl-irssi
/echo HARNESS:SECOND_UNLOAD_COMPLETE
/quit
COMMANDS
status=$?
set -e

cat "$output"
if [ "$status" -eq 124 ] || [ "$status" -eq 137 ]; then
	printf '%s\n' "Irssi lifecycle test exceeded its ${TIMEOUT}s timeout." >&2
	exit 1
fi
if [ "$status" -ne 0 ]; then
	printf '%s\n' "Irssi lifecycle test exited with status $status." >&2
	exit 1
fi

assert_count() {
	marker=$1
	expected=$2
	actual=$(grep -F -c "$marker" "$output" || true)
	if [ "$actual" -ne "$expected" ]; then
		printf '%s\n' "Expected '$marker' $expected time(s), observed $actual." >&2
		exit 1
	fi
}

assert_count 'HARNESS:IRSSI_STARTED_OFFLINE' 1
assert_count 'You are running autodl-irssi v2.6.2' 2
assert_count 'autodl-irssi v2.6.2 is now disabled!' 2
assert_count 'Successfully loaded tracker files' 2
assert_count 'HARNESS:FIRST_LOAD_COMPLETE' 1
assert_count 'HARNESS:FIRST_UNLOAD_COMPLETE' 1
assert_count 'HARNESS:SECOND_LOAD_COMPLETE' 1
assert_count 'HARNESS:SECOND_UNLOAD_COMPLETE' 1

if grep -Eiq 'script (error|not found)|fatal perl|uncaught exception|segmentation fault|core dumped|undefined subroutine|can.t locate|forced termination' "$output"; then
	printf '%s\n' 'Irssi output contains a fatal lifecycle diagnostic.' >&2
	exit 1
fi

printf '%s\n' 'Offline Irssi lifecycle completed two load/unload cycles.'
