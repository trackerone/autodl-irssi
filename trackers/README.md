# Tracker definitions

This directory is the canonical tracker-definition source for this fork of
autodl-irssi. Definitions are stored as ordinary source files so changes can be
reviewed and tested against the application parser in the same repository.

The initial 77-file snapshot was imported unchanged from
[`mkgeeky/autodl-trackers`](https://github.com/mkgeeky/autodl-trackers) at
commit `a91caa41e27ae6b0f542da2ba339a9665c66b023`. `SOURCE.json` records the
machine-readable provenance. The `Upload.cx.tracker` file found only in that
project's v290.7.2 release archive was not imported because it was absent from
the source commit.

Imported files retain their original contents, attribution, and any individual
license notices. Future changes in this repository should preserve applicable
notices and explain the tracker behavior being changed.

The current runtime updater still consumes published tracker releases. Building
those release artifacts from this directory and moving the updater to this
repository are separate follow-up changes.
