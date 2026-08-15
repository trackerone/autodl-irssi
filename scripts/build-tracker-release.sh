#!/bin/sh
set -eu

for executable in perl zip unzip sha256sum cmp; do
	if ! command -v "$executable" >/dev/null 2>&1; then
		printf '%s\n' "Tracker release builder requires '$executable'." >&2
		exit 1
	fi
done

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
version_file=$repo/trackers/VERSION
[ -f "$version_file" ] || { printf '%s\n' 'Missing trackers/VERSION.' >&2; exit 1; }
IFS= read -r version <"$version_file"
printf '%s\n' "$version" | grep -Eq '^[0-9]+([.][0-9]+)*$' || {
	printf '%s\n' "Invalid tracker release version '$version'." >&2
	exit 1
}

output_dir=${1:-$repo/dist}
mkdir -p "$output_dir"
output_dir=$(CDPATH= cd -- "$output_dir" && pwd)
archive=$output_dir/autodl-trackers-v$version.zip
checksum=$archive.sha256

expected_count=$(perl -MJSON::PP -0777 -e '
	my $data = decode_json(<STDIN>);
	die "Invalid tracker_files metadata\n"
		unless $data->{tracker_files} && $data->{tracker_files} =~ /^\d+$/;
	print $data->{tracker_files};
' <"$repo/trackers/SOURCE.json")
actual_count=$(find "$repo/trackers" -maxdepth 1 -type f -name '*.tracker' | wc -l)
[ "$actual_count" -eq "$expected_count" ] || {
	printf '%s\n' "Expected $expected_count tracker files, found $actual_count." >&2
	exit 1
}

stage=$(mktemp -d "${TMPDIR:-/tmp}/autodl-trackers-release.XXXXXX")
cleanup() {
	trap - EXIT HUP INT TERM
	rm -rf "$stage"
}
trap cleanup EXIT HUP INT TERM

cp "$repo"/trackers/*.tracker "$stage/"
find "$stage" -maxdepth 1 -type f -name '*.tracker' -exec touch -t 198001010000.00 {} +
(
	cd "$stage"
	find . -maxdepth 1 -type f -name '*.tracker' -print | LC_ALL=C sort | zip -X -q "$archive" -@
)

find "$repo/trackers" -maxdepth 1 -type f -name '*.tracker' -exec basename {} \; | LC_ALL=C sort >"$stage/expected-members"
unzip -Z1 "$archive" | LC_ALL=C sort >"$stage/archive-members"
cmp "$stage/expected-members" "$stage/archive-members" || {
	printf '%s\n' 'Tracker release archive members do not match the source directory.' >&2
	exit 1
}

while IFS= read -r member; do
	unzip -p "$archive" "$member" | cmp - "$repo/trackers/$member" || {
		printf '%s\n' "Archive contents differ for '$member'." >&2
		exit 1
	}
done <"$stage/expected-members"

(
	cd "$output_dir"
	sha256sum "$(basename "$archive")" >"$(basename "$checksum")"
)

printf '%s\n' "Built $archive with $actual_count tracker files."
printf '%s\n' "Wrote $checksum."
