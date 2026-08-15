# Tracker audit

The 77 definitions imported from `mkgeeky/autodl-trackers` were audited on
2026-08-15 before the first fork-owned tracker release. This audit makes the
source directory release-ready; it does not publish a tag or GitHub release.

## Upstream delta review

The imported commit already contains the latest merged tracker list. The open
dead-tracker report only names DanishBytes, which upstream removed in June 2024
and restored with new IRC hosts in December 2024. The restored definition is in
the imported snapshot, so the audit does not remove it.

Two post-snapshot reports required review:

* [`mkgeeky/autodl-trackers#24`](https://github.com/mkgeeky/autodl-trackers/issues/24)
  reports that PassThePopcorn moved to a compact, pipe-delimited announcement.
  `PassThePopcorn.tracker` now accepts that format, maps its category, origin,
  freeleech flag, byte size and download key, and retains the historical format
  as a compatibility fallback.
* [`mkgeeky/autodl-trackers#26`](https://github.com/mkgeeky/autodl-trackers/pull/26)
  was closed without merge, but points to nCore's own published definition at
  `https://static.ncore.pro/static/nCore.tracker`. That site-owned file was
  reachable during the audit and names `irc.ncore.pro`. The local definition
  adopts that endpoint and its `nC` display casing. It also records the
  announced size in the production `torrentSize` field instead of a temporary
  variable.

## Verification boundary

The packaged-Irssi integration test still parses and reloads all 77 unique
tracker types. It additionally feeds representative current PassThePopcorn and
nCore announcements through the production parser and verifies the resulting
metadata and authenticated download URLs.

This is an offline compatibility audit. Private IRC channels and authenticated
torrent downloads were not contacted, so it does not claim that every tracker
is live or that every private announce variant has been observed. `VERSION`
remains `291.0`; publishing is a separate, explicit action.
