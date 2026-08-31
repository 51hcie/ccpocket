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
