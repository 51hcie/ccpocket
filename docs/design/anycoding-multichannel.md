# AnyCoding multichannel connection

The configured URL remains the user's anchor. A Bridge advertises current LAN
IPv4 and global IPv6 addresses in `/health`, with a persistent per-installation
identity. These are candidate addresses, not claims of cellular reachability.
The app probes candidates without credentials and only selects matching Bridge
identities. Saved candidates allow fallback when the anchor is unavailable.

Probe routes concurrently with bounded timeouts. Keep a healthy route unless a
candidate is substantially faster; defer optional switching during active work.
On disconnect choose a verified reachable alternative. A route change is a
transport reconnect, not a different project/server: retain session and pending
input identity and use the existing acknowledgement/reconciliation protocol.
Never create or replay a task simply because an address changed.

Settings display current route, measured latency, alternate addresses (including
IPv6 when on LAN), reachability, and selection reason. Copying an address excludes
credentials. Legacy servers without discovery continue using their configured URL.

Acceptance: discovery filters/identity persistence, concurrent probes and stale
results, identity mismatch, custom endpoint isolation, anti-flapping and fallback,
session preservation and no new input on route switch; emulator-5556 fresh start,
settings/copy/refresh, LAN and IPv6 tests. Mac-local IPv6 tests do not prove
mobile-carrier ingress. Do not operate emulator-5554 or stop production 8766.

## HTTP recovery (Build 230)

APK transfers have a 20-second header/inactivity deadline and at most three
attempts. Abort timed-out HTTP requests, discard partial files, and re-evaluate
the current Bridge route before retrying transient network errors. Each attempt
starts from byte zero; do not treat a 206 response as a complete APK. Require
manifest size and streaming SHA-256 verification before enabling installation.
Integrity/status errors are terminal, not automatic retries.

Monitoring permits only one pending request per current route. A route change
starts a new generation; older results/errors cannot overwrite the new route's
display. Route discovery events without an actual URL change do not trigger
additional requests. Dispose invalidates outstanding generations.

Build 231 adds explicit cancellation (also on sheet disposal), retry attempt and
verification feedback, and progress rendering throttled to 150 ms except for
initial/final progress. Cancellation never retries and removes partial files.
The checksum label describes integrity only; Android verifies installation
signatures. Failed monitor refreshes retain data with a visible stale-data notice
that clears after a successful refresh.
