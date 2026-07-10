# STATE — pointer

> One read = full resume. Update at the end of every working session.

## Next action (one sentence)

"Doesn't track reliably" is unroutable until the stream is observable —
first packet: per-hop frame counters + end-to-end latency log in
`mac_pointer_server.py` (10 s windows, sent/received/dropped per transport),
so the symptom lands on a row of the bug-routing table instead of a vibe.

## Current stage & gate

Stage 4–5 of the kit pipeline. Standing bug: **tracking unreliable**
(Ben, 2026-07-10 — symptom not yet localized: candidate rows are BLE
backpressure, UDP drops, filter dt after reconnect, stale-frame handling).
Also open: Swift bake-off (fixes implementer routing), test target, and CI
install (kit now requires CI at Stage 2 — pointer predates that, install
`ci/swift-xcode.yml` with the first packet).

## Recently done

| Date | What | Evidence |
|---|---|---|
| 2026-07-09 | BLE direct Watch→Mac transport | commit 5ccd9ec |
| 2026-07-09 | UDP binary transport, adaptive EMA, accel+deadzone | commit 375b8c1 |
| 2026-07-10 | Pipeline instance created (this dir) | Fable session |
| 2026-07-10 | **Builds in Xcode confirmed** (registry next-inch closed) | Ben, verbal — no CI record yet; tracking still unreliable |

## Open decisions for Ben

| # | Decision | Options prepared | Deadline |
|---|---|---|---|
| 1 | Native `pointer Mac` app vs Python server as the shipping sink | (a) Python stays canonical, Mac app archived (b) converge on native | before keyboard feature (#3 roadmap) |
| 2 | Publish kit repo to GitHub | `gh repo create` when ready — kit is committed locally | whenever |

## Bodies buried

- Control frames (click/calib/reset) over UDP trust LAN delivery — no
  seq/ack/dedup yet. A dropped click will eventually be blamed on BLE.
- `pointer/` (iOS) and `pointer Mac/` contain near-duplicate
  MacMotionReceiver/MouseController/CursorAccessibility files — drift risk.
- Simulator can't do BLE (pill shows SIM); anything BLE needs the physical
  watch, i.e. Ben.
