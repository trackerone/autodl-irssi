#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
first=$(mktemp -d "${TMPDIR:-/tmp}/autodl-trackers-package-first.XXXXXX")
second=$(mktemp -d "${TMPDIR:-/tmp}/autodl-trackers-package-second.XXXXXX")
cleanup() {
	trap - EXIT HUP INT TERM
	rm -rf "$first" "$second"
}
trap cleanup EXIT HUP INT TERM

"$repo/scripts/build-tracker-release.sh" "$first"
"$repo/scripts/build-tracker-release.sh" "$second"

version=$(sed -n '1p' "$repo/trackers/VERSION")
archive=autodl-trackers-v$version.zip
[ -f "$first/$archive" ] || { printf '%s\n' "Missing $archive." >&2; exit 1; }
[ -f "$first/$archive.sha256" ] || { printf '%s\n' "Missing $archive.sha256." >&2; exit 1; }
(cd "$first" && sha256sum -c "$archive.sha256")
cmp "$first/$archive" "$second/$archive" || {
	printf '%s\n' 'Repeated tracker package builds were not byte-identical.' >&2
	exit 1
}

member_count=$(unzip -Z1 "$first/$archive" | wc -l)
[ "$member_count" -eq 77 ] || {
	printf '%s\n' "Expected 77 flat archive members, found $member_count." >&2
	exit 1
}
if unzip -Z1 "$first/$archive" | grep -q '/'; then
	printf '%s\n' 'Tracker release archive contains a directory path.' >&2
	exit 1
fi

printf '%s\n' "Tracker release package validation passed: $archive, 77 flat members, deterministic checksum."
