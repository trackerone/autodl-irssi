# Revival baseline

This document records the observed state of release 2.6.2 and deliberately does
not imply that the external integrations are production-ready.

## Requirements and assumptions

Every application module declares Perl 5.8 as its language floor. That is a
historical declaration, not evidence that Perl 5.8 remains supported. The
repeatable Ubuntu 24.04 baseline uses the supported Perl 5.38 supplied by
Ubuntu 24.04.
The application requires Irssi built with Perl support; the baseline uses the
Ubuntu 24.04 Irssi package rather than pinning an upstream build.

The direct non-core Perl dependencies are `Archive::Zip`, `HTML::Entities`
(from HTML::Parser), `JSON`, `Net::SSLeay`, and `XML::LibXML`. `JSON::XS` is an
optional accelerator. Core modules used by the code include Digest::SHA,
Encode, File::Spec, File::Temp, POSIX, Socket, Time::HiRes, and Time::Local.
The corresponding development packages are recorded in `Dockerfile`, the CI
workflow, and `cpanfile`. CPAN source builds may additionally need a compiler,
`make`, OpenSSL headers, and libxml2 headers. At runtime Irssi is the external
program; rTorrent/SCGI, an FTP server, a uTorrent-compatible WebUI, a watch
directory or a configured command are needed only for their respective upload
actions. ruTorrent is not part of this repository.

## Installation, update, and paths

The documented manual installation expands a release archive beneath
`~/.irssi/scripts`, copies `autodl-irssi.pl` to
`~/.irssi/scripts/autorun`, and creates `~/.autodl/autodl.cfg`. Irssi's script
directory contains `AutodlIrssi/` and its `trackers/` directory. Runtime state
is kept under `~/.autodl`: `autodl.cfg`, optional `autodl2.cfg`,
`DownloadHistory.txt`, and `AutodlState.xml`.

The in-process updater queries the GitHub releases APIs for the application and
tracker definitions, downloads release ZIP archives, and replaces files. Auto
update is the configuration default. Application updates retain the historical
`autodl-community/autodl-irssi` source. Tracker updates list releases from
`trackerone/autodl-irssi`, select stable `trackers-v...` tags, and consume the
asset URL returned by GitHub release metadata.

## Repeatable Ubuntu 24.04 baseline

Run locally with a compatible Perl and the dependencies from `cpanfile`:

```sh
make check
```

Or build and run the isolated Ubuntu environment:

```sh
docker build -t autodl-irssi-dev .
docker run --rm --network none autodl-irssi-dev
```

The image command performs syntax checks, deterministic tests, and the packaged
Irssi lifecycle integration test. The container has no runtime network, and the
Irssi harness explicitly disables IRC auto-connect and update checks.

## What currently works and is tested

The baseline confirms, without external services:

* module loading for Bencoding, FilterState, LineBuffer, RtorrentCommands, and
  TextUtils;
* valid and invalid bencoded input, including nested torrent metadata;
* byte-size and elapsed-time conversion, IRC formatting removal, wildcard
  conversion, and release-name canonicalisation;
* line assembly across input chunks and final-buffer flushing;
* deterministic rTorrent command string construction (not command execution);
* UTC hour/day/week filter-state boundaries and counter increments;
* two load/unload cycles of the real `autodl-irssi.pl` entry point in one
  packaged Irssi process, using an isolated temporary home and local fixtures;
* all 77 imported production tracker definitions parsing to unique tracker
  types and reloading through the production `TrackerManager`.

These are characterization tests: they preserve current results rather than
declaring every historical edge case correct.

## Integration-only or currently untested components

IRC connection and live announce matching, live torrent downloads, HTTP redirects,
general TLS behavior, FTP, sockets, live rTorrent,
uTorrent WebUI, watch folders, external commands, WOL, the local GUI server, application
updater file replacement, and ruTorrent all require later integration fixtures or
services. Tracker updater replacement has one controlled offline characterization below.
SCGI/XML-RPC has one loopback and Unix-socket characterization below. The lifecycle
harness covers configuration parsing and the whole module graph in Irssi without
claiming coverage of other service behavior.

## Issue 190 nonblocking TLS regression

The dedicated `make test-https-stall` integration reproducer exercises the
production `HttpRequest`, `SslSocket`, `SocketBase`, Net::SSLeay, and Irssi
event-loop path without contacting an external service. A loopback-only
`IO::Socket::SSL` fixture completes the TLS handshake, validates the received
GET request, then withholds all HTTP response bytes for 2500 ms before returning
a complete `HTTP/1.1 200 OK` response. The fixture uses an operating-system-
selected ephemeral port, FIFO readiness synchronization, a committed test-only
certificate, hard timeouts, and deterministic cleanup.

Immediately after the production HTTPS request has been written, the test
schedules an independent 500 ms Irssi timer. Net::SSLeay documents
`ssl_read_all()` as providing true blocking semantics, but the client selected
that helper on Net::SSLeay 1.84 and newer even though its socket and Irssi input
handlers are nonblocking. The fixture previously recorded the HTTP callback
before the already-expired timer, demonstrating a bounded 2500 ms event-loop
stall inside the TLS read.

`SslSocket` now performs one low-level `SSL_read` through `Net::SSLeay::read()`
per readiness event on every supported Net::SSLeay version. `WANT_READ` and
`WANT_WRITE` continue through the existing Irssi handler selection. The
regression requires the independent timer to fire before the delayed HTTP
callback, which then succeeds exactly once. This removes the reproduced blocking
condition associated with issue #190 without changing HTTP retry policy or
timeouts. The upstream report's intermittent permanent hang is not reproduced,
so this fix is limited to the demonstrated event-loop stall. No version, tag, or
release is created.

## Issue 191 offline characterization

The dedicated `make test-http-incomplete-header` integration reproducer
exercises the production `HttpRequest`, `Socket`, `SocketBase`, retry timer,
and packaged Irssi event loop without contacting GitHub, ruTorrent, IRC, or
another external service. A loopback fixture accepts a real GET request, writes
`HTTP/1.1 200 OK` and the beginning of a header field, then closes the
connection before the terminating blank line. It repeats this deterministic
partial response for every production retry.

With `maxDownloadRetryTimeSeconds` set to 3 seconds for this test only, both
the direct Ubuntu 24.04 CI run and the network-disabled development container
observe three requests and three partial responses. Irssi processes an
independent 500 ms responsiveness timer between attempts. After the retry
window, the final callback occurs exactly once with
`Timed out! Error: Could not parse HTTP response header`; Irssi then completes
a one-second settling interval and exits normally.

This reproduces the parser/retry error text reported in issue #191 at the shared
HTTP boundary. It does not exercise the external ruTorrent client, reproduce
its settings dialog failure, prove that the updater produced the original
incomplete response, establish a root cause, or propose a production fix. No
production HTTP parsing, retry, timeout, updater, or GUI behavior is changed.

## Issue 210 offline characterization

The dedicated `make test-http-401` integration reproducer characterizes the
HTTP behavior associated with issue #210 without contacting a tracker or IRC
server. It starts the Ubuntu 24.04 packaged Irssi in a pseudo-terminal with a
fresh home, loads the real `autodl-irssi.pl`, and invokes
`AutodlIrssi::MatchedRelease::start()` with narrowly scoped test substitutes for
download-history persistence and announce-parser metadata. The subsequent path
uses the production `MatchedRelease`, `HttpRequest`, `Socket`, and `SocketBase`
code, including Irssi input handlers and timer callbacks.

With `maxDownloadRetryTimeSeconds` set to 3 seconds for this test only, the
loopback fixture observes three GET requests: the initial request and two
requests started by the production 2000 ms retry timer. Every response is
`401 Unauthorized`. The terminal callback occurs once after the retry window
has elapsed and reports `Timed out! Error: HTTP error 'HTTP/1.1 401 Unauthorized'`.
Irssi processes a separate 500 ms responsiveness timer while the HTTP request
is pending, remains alive for a one-second post-callback settling interval, and
then exits normally. The fixture binds `127.0.0.1` on an operating-system-chosen
ephemeral port and uses a FIFO to publish readiness, rather than a sleep.

This evidence reproduces the 401 retry trigger and repeated requests. It does
not reproduce or measure the reported 100% CPU symptom, and it does not
establish a root cause or proposed fix. No production retry policy, interval,
default, HTTP parsing, or socket behavior is changed by the characterization.

## Tracker release/updater sandbox

The dedicated `make test-tracker-update` integration exercises the complete
tracker release/update path without contacting GitHub. It builds the current
77-file release archive and checksum with the production builder, returns
release metadata through a fixture transport, and drives the production
`Updater` inside a packaged Irssi process. The release workflow runs this same
test before it can publish tracker assets.

The updater requires both the versioned ZIP and its `.sha256` asset. The sandbox
verifies the request order, rejects missing assets and a checksum-mismatched ZIP
before changing the installation, then installs all 77 files and reloads all 77
tracker types. Archive members must be flat, uniquely named `.tracker` files,
and every definition must parse with a unique tracker type before installation.

Installation now stages and validates the complete package before moving any
existing tracker file. Existing files are backed up during replacement; an
injected mid-install failure proves that the partially installed package is
removed and the exact prior file set and contents are restored. A traversal
member is also rejected without writing outside the destination. This closes
the destructive partial-install path found during the sandbox audit, but does
not reproduce issue #198's original filesystem ownership or path conditions.
No version, tag, or release is created by the test.

## Historical tracker release source

Before consolidation, the tracker updater was moved from the inactive
`autodl-community/autodl-trackers` v284 line to
`mkgeeky/autodl-trackers`, whose latest observed release was v290.7.2. That
release parser required an asset named from the reported version
(`v290.7.2.zip`) and used its API-provided `browser_download_url`.

The offline integration fixture exercises the production release parser,
version check, download callback, archive extraction, replacement, and tracker
reload without contacting either repository. A committed manifest records the
directly inspected v290.7.2 asset: SHA-256
`22fcabf78b9b2034a0c9f022b2cdfcfa4b2d52b9b2088b2aedee42b96b6177b5`,
78 unique `.tracker` members, and no directory prefixes. At inspection time the
source repository's `master` contained 77 tracker files; the release-only file
was `Upload.cx.tracker`. This external release is retained only as migration
provenance and a historical manifest fixture.

## Imported tracker definitions

The repository now contains a canonical `trackers/` source directory. Its
initial 77 definitions were imported from `mkgeeky/autodl-trackers` commit
`a91caa41e27ae6b0f542da2ba339a9665c66b023`; `trackers/SOURCE.json` records
the provenance, count, and two parser-compatibility repairs. Individual license
notices are preserved. `Upload.cx.tracker`, which existed in the v290.7.2
release archive but not in that source commit, is intentionally not imported.

The dedicated `make test-trackers` packaged-Irssi check requires every imported
file to parse through the production `TrackerXmlParser`, requires all tracker
types to be unique, reloads them through the production `TrackerManager`, and
asserts that all 77 remain active. It also parses representative current
PassThePopcorn and nCore announcements and verifies their extracted metadata
and authenticated download URLs. It runs without IRC or external network.

The 2026-08-15 release-readiness audit reviewed the remaining upstream tracker
reports. PassThePopcorn's compact pipe-delimited announcement format is now
supported alongside the historical format. nCore now uses the tracker-owned
`irc.ncore.pro` endpoint published by nCore's own definition, and its announced
size populates the production size field. `trackers/AUDIT.md` records the
evidence and test boundary. The audit does not change `trackers/VERSION`, create
a tag, or publish a release.

## Current release years

The core release-name parser inherited a fixed `2000-2019` year range, so
movies and dated TV releases from 2020 onward did not contribute their year or
`YYYY-MM-DD` value to extracted metadata and title boundaries. This is the bug
reported by upstream PR #194. The parser now accepts `2000-2099` consistently
in its standalone-year, date, and TV-date checks while retaining the historical
1930 lower bound and rejecting 2100.

The deterministic regression test covers 2020 and 2026 movies, a 2026 dated TV
release, a TV title whose 2005 year must remain in the title, and the century
boundaries. This core fix does not change `VERSION`, create a tag, or publish a
release.

## Configuration parser fixtures

Configuration diagnostics are now owned by `ConfigFileParser` instead of being
sent directly through `Globals` and Irssi. Callers can inspect the collected
diagnostics, and the production startup path injects the existing error-message
handler so runtime output is unchanged. This lets the config parser and its
`AutodlConfigFileParser` subclass load and run without an Irssi process.

Deterministic fixtures characterize option conversion, filter construction,
server/channel normalization, source line diagnostics, unknown input, bare
wildcards, and invalid upload types. The existing tracker-definition integration
continues to cover production tracker XML and representative announce parsing.
No version, tag, or release is created by these tests.

## SCGI/XML-RPC/rTorrent sandbox

The dedicated `make test-scgi-xmlrpc` integration drives the production `Scgi`,
`Socket`, `DomainSocket`, `XmlRpcSimpleCall`, `XmlRpcResponseParser`, and
`RtorrentCommands` modules inside packaged Irssi. Two local fixture servers cover
both supported transports: an operating-system-selected TCP loopback port and an
isolated Unix-domain socket. Neither fixture starts rTorrent or contacts an
external service.

Each server validates the SCGI netstring framing, required headers, content
length, XML-RPC method, XML escaping, torrent path, and generated rTorrent command
string. The TCP fixture returns a successful string value after a delay that lets
an independent Irssi timer run. The Unix-socket fixture returns an XML-RPC fault;
the production parser reports its code and message exactly once. This
characterizes transport selection and request/response behavior without changing
the production SCGI, XML-RPC, socket, or rTorrent upload implementation. No
version, tag, or release is created by the sandbox.

`trackers/VERSION` identifies the fork-owned tracker release. The shared
`scripts/build-tracker-release.sh` builder creates a deterministic flat ZIP,
verifies its 77 names and contents, and writes a SHA-256 checksum. CI runs the
builder twice and requires byte-identical output. The `Publish tracker release`
workflow publishes the same output under `trackers-v<VERSION>` either by manual
dispatch or a matching tag push.

The production updater now lists releases from `trackerone/autodl-irssi` and
chooses the newest non-draft, non-prerelease `trackers-v...` entry. This prefix
keeps tracker and application releases unambiguous in one repository. The
offline updater fixture includes both release kinds plus a tracker prerelease,
then verifies metadata selection, archive replacement, and tracker reload.

## Confirmed blockers and repository comparison

No application compatibility defect was found in the deterministic subset on
Perl 5.38. The checked-out history contains release 2.6.2 (`b534cbe`).

The following are verified descriptions of upstream reports, not symptoms
reproduced by this work:

* [Issue #190 — “Hanging randomly when downloading torrent”](https://github.com/autodl-community/autodl-irssi/issues/190)
  reports an intermittent HTTPS torrent download stalling during nonblocking
  SSL reads and leaving the Irssi UI hung. The relevant review boundaries are
  `AutodlIrssi/HttpRequest.pm`, `AutodlIrssi/SslSocket.pm`, and the socket
  lifecycle modules `SocketBase.pm` and `Socket.pm`.
* [Issue #191 — “MyDialogManager._OnDownloadedFiles:No Settings Found : could not parse HTTP response header”](https://github.com/autodl-community/autodl-irssi/issues/191)
  reports ruTorrent settings and updater requests timing out with HTTP
  response-header parsing errors. Boundaries are `HttpRequest.pm`,
  `GuiServer.pm`, and `Updater.pm`; ruTorrent itself is outside this repository.
* [Issue #198 — “Tracker update not installing”](https://github.com/autodl-community/autodl-irssi/issues/198)
  reports the updater claiming current versions or successful completion while
  an installed tracker definition remains outdated. Boundaries are
  `Updater.pm`, `TrackerManager.pm`, and tracker file/path handling in `Dirs.pm`.
* [Issue #210 — “irssi goes into 100% CPU utilization when it can't download a torrent with 401 error.”](https://github.com/autodl-community/autodl-irssi/issues/210)
  associates an HTTP 401 torrent response with Irssi reaching 100% CPU usage.
  Boundaries are `HttpRequest.pm`, `ActiveConnections.pm`, `SocketBase.pm`, and
  `Socket.pm`.

These mappings identify code to inspect. The demonstrated HTTPS event-loop stall
associated with issue #190 is fixed and guarded by the delayed-response
regression above. The incomplete-header parser/retry result associated with issue
#191, the controlled tracker replacement and reload path associated with issue
#198, and the repeated HTTP behavior associated with issue #210 are
characterized above. Issue #190's intermittent permanent hang, issue #191's
external ruTorrent settings failure and original upstream cause, issue #198's
reported stale installed file, and issue #210's CPU symptom are not reproduced
here.

## Security observations

These observations are review prompts, not reproduced vulnerabilities:

* the installation documentation pipes data derived from a shortened HTTP URL
  into download tooling and should eventually be replaced by an authenticated,
  checksum-verifiable installation path;
* tracker updates require the published SHA-256 asset and validate all tracker
  definitions transactionally, while application updates still lack an
  artifact checksum or signature verification step;
* the custom HTTP/TLS/socket implementation needs focused review for certificate
  and hostname verification, protocol policy, redirects, framing, timeouts, and
  partial reads before it is treated as a secure modern client;
* configuration can intentionally invoke external tools and contains credentials
  for services, so permissions, argument handling, and log redaction need
  integration-level review;
* the GUI server listens on loopback, but its authentication and message limits
  still require dedicated tests.

## Recommended next phases

1. Build minimal offline reproducers for the recorded upstream reports before
   considering fixes.
2. Configuration diagnostics are isolated from Globals/Irssi, with fixture
   coverage for config and filter parsing. Tracker XML and representative
   announce parsing are covered by the tracker-definition integration.
3. Local-only fake servers now characterize HTTP/TLS/socket and SCGI/XML-RPC
   behavior; live rTorrent behavior remains outside the repository boundary.
4. Address HTTP/TLS/socket and updater findings in separate, narrowly scoped
   changes. The demonstrated blocking TLS read is fixed; the remaining findings
   and later rTorrent/ruTorrent integration stay separate.
