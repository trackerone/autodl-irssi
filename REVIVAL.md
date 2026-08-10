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
docker run --rm autodl-irssi-dev
```

The image command performs syntax checks for the independently loadable modules
and runs all tests. It does not connect to IRC or start Irssi interactively.

## What currently works and is tested

The baseline confirms, without external services:

* module loading for Bencoding, FilterState, LineBuffer, RtorrentCommands, and
  TextUtils;
* valid and invalid bencoded input, including nested torrent metadata;
* byte-size and elapsed-time conversion, IRC formatting removal, wildcard
  conversion, and release-name canonicalisation;
* line assembly across input chunks and final-buffer flushing;
* deterministic rTorrent command string construction (not command execution);
* UTC hour/day/week filter-state boundaries and counter increments.

These are characterization tests: they preserve current results rather than
declaring every historical edge case correct.

## Integration-only or currently untested components

Irssi startup, signal/timer registration, IRC connection and announce handling,
tracker XML definitions (not present in this source checkout), live torrent
downloads, HTTP redirects, TLS, FTP, sockets, SCGI/XML-RPC/rTorrent, uTorrent
WebUI, watch folders, external commands, WOL, the local GUI server, updater file
replacement, and ruTorrent all require later integration fixtures or services.
Configuration parsing depends on the Globals/Irssi layer and is not mocked in
this first slice; honest isolation requires a small injectable message boundary.
The whole module graph also has load-time Irssi and TLS side effects, so CI does
not pretend that loading five isolated modules is a full application startup.

## Confirmed blockers and repository comparison

No application compatibility defect was found in the deterministic subset on
Perl 5.38. A full startup cannot be confirmed without an Irssi process and
tracker definitions. The checked-out history ends at release 2.6.2 (`b534cbe`).
Network access from the development environment returned HTTP 403 while fetching
both `trackerone/autodl-irssi` and `autodl-community/autodl-irssi`; consequently,
the fork/upstream comparison and current issue text could not be independently
refreshed. No divergence claim is made.

Upstream issues [#190](https://github.com/autodl-community/autodl-irssi/issues/190),
[#191](https://github.com/autodl-community/autodl-irssi/issues/191),
[#198](https://github.com/autodl-community/autodl-irssi/issues/198), and
[#210](https://github.com/autodl-community/autodl-irssi/issues/210) must be
triaged against their live descriptions before fixes begin. Relevant code
boundaries for that triage are `AutodlIrssi/HttpRequest.pm` and
`AutodlIrssi/SslSocket.pm` (HTTP/TLS), `AutodlIrssi/SocketBase.pm`,
`AutodlIrssi/Socket.pm`, and `AutodlIrssi/DomainSocket.pm` (socket lifecycle),
`AutodlIrssi/Updater.pm` (updates), and `AutodlIrssi/Scgi.pm`,
`AutodlIrssi/XmlRpc.pm`, and `AutodlIrssi/RtorrentCommands.pm` (rTorrent).
Those references identify review locations only; none of the four issues has
been reproduced in this work.

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

1. Fetch and record the fork/upstream diff and issue descriptions in a networked
   environment; map each report to a minimal reproducer.
2. Add an Irssi test harness that starts with a temporary home/config and local
   tracker fixtures, then verify load/unload without a network connection.
3. Isolate configuration diagnostics from Globals/Irssi and characterize config,
   filter, tracker XML, and announce parsing with fixtures.
4. Build local-only fake servers for HTTP/TLS/socket and SCGI/XML-RPC behavior.
5. Only after those tests exist, address HTTP/TLS/socket and updater findings in
   separate, narrowly scoped changes, followed by rTorrent and ruTorrent
   integration work.
