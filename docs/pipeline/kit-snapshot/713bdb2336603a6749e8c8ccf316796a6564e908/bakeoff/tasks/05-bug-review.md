# Bake-off task 05 — Bug review

Provide with: `pointer Watch App/BLETransport.swift` verbatim (it's the
newest, least-reviewed file — Watch-side BLE central with reconnect/backoff
and acknowledged control writes).

---

Context: this file is the Watch side of a custom BLE link to a Mac
peripheral. Motion frames are unacknowledged writes at 15 Hz and may drop;
control frames (click/calibrate/reset) use acknowledged writes with
queue/retry. The Watch auto-scans and reconnects with backoff.

Task: review this file for Swift concurrency, lifecycle, and Apple API
mistakes. **Do not rewrite it unless a defect genuinely requires it.**

1. CoreBluetooth delegate threading: which queue do callbacks arrive on,
   and is shared state touched from it safely?
2. Lifecycle: scanning/connection state across app background/foreground,
   watch wrist-down, and `CBCentralManager` state restoration.
3. The retry queue: can a control frame be delivered twice? Delivered after
   a reconnect to a stale characteristic? Lost silently?
4. Backoff correctness: can scan-and-reconnect loops stack (two concurrent
   scan attempts)? Does backoff reset appropriately on success?
5. Write-without-response backpressure: what happens at 15 Hz when
   `canSendWriteWithoutResponse` is false?

Deliver: numbered findings with file/line, severity (blocking/should-fix/
nit), the minimal fix for each, and explicitly: which findings you are
CONFIDENT about vs SUSPICIOUS about. Unfounded confident claims score
against you.
