# Tracker definitions

This directory is the canonical tracker-definition source for this fork of
autodl-irssi. Definitions are stored as ordinary source files so changes can be
reviewed and tested against the application parser in the same repository.

The initial 77-file snapshot was imported from
[`mkgeeky/autodl-trackers`](https://github.com/mkgeeky/autodl-trackers) at
commit `a91caa41e27ae6b0f542da2ba339a9665c66b023`. `SOURCE.json` records the
machine-readable provenance. The `Upload.cx.tracker` file found only in that
project's v290.7.2 release archive was not imported because it was absent from
the source commit.

Two source files required minimal parser-compatibility repairs: HUNO's custom
RSS-key setting and line-matched operations were expressed using unsupported
tags, and LustHive used `name` instead of `value` on one string fragment. These
repairs are recorded in `SOURCE.json` and validated by the production parser.
The subsequent release-readiness audit and the reviewed PTP/nCore deltas are
recorded in [`AUDIT.md`](AUDIT.md).

Imported files retain their original attribution and any individual license
notices. Future changes in this repository should preserve applicable
notices and explain the tracker behavior being changed.

`VERSION` is the release version for this directory. Run
`scripts/build-tracker-release.sh` to create a deterministic, flat archive named
`autodl-trackers-v<VERSION>.zip` plus its SHA-256 checksum. The builder rejects
count mismatches and verifies every archived file against this directory.

The `Publish tracker release` workflow publishes those files under a
`trackers-v<VERSION>` tag. It can be started manually after changing `VERSION`,
or by pushing the matching tag. The runtime updater lists releases from this
repository and selects the newest stable `trackers-v...` release, independently
of application releases in the same repository.
