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
update is the configuration default. This mechanism is documented here but is
intentionally not exercised or changed by the baseline.

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
  packaged Irssi process, using an isolated temporary home and local fixtures.

These are characterization tests: they preserve current results rather than
declaring every historical edge case correct.

## Integration-only or currently untested components

IRC connection and announce handling, production tracker XML definitions, live torrent
downloads, HTTP redirects, TLS, FTP, sockets, SCGI/XML-RPC/rTorrent, uTorrent
WebUI, watch folders, external commands, WOL, the local GUI server, updater file
replacement, and ruTorrent all require later integration fixtures or services.
The lifecycle harness covers configuration parsing and the whole module graph in
Irssi without claiming coverage of service behavior.

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

These mappings identify code to inspect only. They neither establish root
causes nor propose fixes. The repeated HTTP behavior associated with issue #210
is characterized above; its reported CPU symptom and the other three reports
are not reproduced here.

## Security observations

These observations are review prompts, not reproduced vulnerabilities:

* the installation documentation pipes data derived from a shortened HTTP URL
  into download tooling and should eventually be replaced by an authenticated,
  checksum-verifiable installation path;
* the updater writes remotely supplied release archives into the installation
  and does not expose an artifact checksum or signature verification step;
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
2. Isolate configuration diagnostics from Globals/Irssi and characterize config,
   filter, tracker XML, and announce parsing with fixtures.
3. Build local-only fake servers for HTTP/TLS/socket and SCGI/XML-RPC behavior.
4. Only after those tests exist, address HTTP/TLS/socket and updater findings in
   separate, narrowly scoped changes, followed by rTorrent and ruTorrent
   integration work.
