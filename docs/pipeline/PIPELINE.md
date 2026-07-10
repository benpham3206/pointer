# pointer — pipeline instance

Bootstrapped from the pipeline kit 2026-07-10. Canonical stages, roles,
packets, and checklists resolve via `KIT.md` → the **pinned immutable
snapshot** in `./kit-snapshot/` — never the live kit path. This file is
pointer-specific. Written by Fable against the actual code; **pending Sol
adversarial review** (snapshot `packets/sol-pipeline-review.md`).

## Current stage

Stage 4–5 (implementation/review loop on an existing app). The PRD-shaped
truth: *"Can a wrist point at and click a 50×50 px target on the external
display in under 2 s, 9 times out of 10, with the lid closed?"* — no
measurement of this exists yet. Getting that number is the standing
acceptance benchmark.

## Architecture & data flow

```
┌─ Apple Watch (watchOS) ───────────────────────────────┐
│ MotionManager.swift   CMDeviceMotion @15Hz            │
│                       adaptive EMA (α 0.08→0.9)       │
│ TrackingRuntime.swift session/runtime                 │
│ BLETransport.swift    BLE central; motion=unacked     │
│                       writes, control=acked+retry     │
└──────┬──────────────────────────────┬─────────────────┘
       │ BLE (preferred, sole         │ WCSession fallback
       │ transport when connected)    ▼
       │                    ┌─ iPhone (iOS) ────────────┐
       │                    │ PhoneWatchReceiver.swift  │
       │                    │ MacForwarder.swift        │
       │                    │  Bonjour + UDP, compact   │
       │                    │  binary frames            │
       │                    │  (type byte + LE float32) │
       │                    └──────────┬────────────────┘
       ▼                               ▼
┌─ Mac ─────────────────────────────────────────────────┐
│ tools/mac_ble_peripheral.swift  (BLE peripheral,      │
│   forwards exact bytes → UDP localhost:19790)         │
│ tools/mac_pointer_server.py  ← single sink            │
│   parse_frame → PointerState → calibration →          │
│   deadzone(2px) → accel curve(1.5) → sensitivity →    │
│   Quartz cursor move/click on --display external      │
│ (parallel native path: "pointer Mac" app target —     │
│   MacMotionReceiver/MouseController/CursorAccessi-    │
│   bility; status: secondary, not the shipping path)   │
└───────────────────────────────────────────────────────┘
```

Loss/staleness boundaries: BLE motion writes (may drop — by design), UDP
motion frames (may drop — harmless), UDP **control** frames (click/calib/
reset — currently trusting LAN reliability; seq/ack+dedup is the known
revisit), BLE reconnect gaps (filter dt handling).

## Module map

| Path | Responsibility |
|---|---|
| `pointer Watch App/MotionManager.swift` | IMU capture, 15 Hz, adaptive EMA |
| `pointer Watch App/BLETransport.swift` | BLE central, reconnect/backoff, control retry queue |
| `pointer Watch App/TrackingRuntime.swift`, `ContentView.swift` | session runtime, watch UI/status pill |
| `pointer/PhoneWatchReceiver.swift` | WCSession receive on iPhone |
| `pointer/MacForwarder.swift` | Bonjour discovery, UDP binary encode |
| `Shared/MotionPayload.swift` | frame payload definitions |
| `tools/mac_ble_peripheral.swift` | Mac BLE peripheral → UDP bridge |
| `tools/mac_pointer_server.py` | sink: parse, calibrate, filter, inject cursor |
| `pointer Mac/*` | native Mac receiver (secondary path) |

## Bug routing (symptom → layer → first check → owner)

| Symptom | Layer | First check | Owner |
|---|---|---|---|
| No motion at all, pill blank | Watch capture | watch UI state; MotionManager start logs; motion permission | implementer |
| Pill says iPhone, expected BLE | BLE transport | Mac server ran with `--ble`? peripheral advertise log; helper dependency error in server output | implementer |
| Pill BLE but cursor frozen | BLE→UDP bridge | peripheral forward log vs server `parse_frame` count | implementer |
| Works on iPhone relay, not BLE | BLE transport | frame bytes identical on both paths? (they must be) | implementer |
| Cursor jitter when still | Filtering | EMA α base, deadzone threshold; feed recorded frames through filter offline | implementer |
| Cursor lags fast motion | Filtering | α ramp / accel curve; rule out transport (frame-rate log first) | implementer |
| Corners unreachable / overshoot | Filtering/calibration | calibration spread, accel exponent, sensitivity | implementer |
| Cursor on wrong screen / offset | Display mapping | `--display` flag; screen enumeration in server log; clamshell state | implementer |
| Moves but won't click | Permissions / control frames | Accessibility permission for the Python process; control-frame receive log | Ben (permission) then implementer |
| Dies after wrist-down / idle | Lifecycle / reconnect | BLE backoff logs, WCSession reachability transitions | implementer |
| Stops when lid closes | Clamshell / display reconfig | display list before/after; server re-enumeration on reconfigure | implementer |
| Intermittent stalls | Transport | UDP drop counting (seq gaps), send-rate log both ends | implementer |

No fix without a row; a bug that fits no row gets its row added first.

## Logging & instrumentation requirements

- Every hop logs **counts, not events**: frames sent/received/dropped per
  10 s window, per transport. One line per state transition (connect,
  disconnect, permission change, display reconfigure), never per frame.
- Frames already carry sample timestamps → server logs end-to-end latency
  (sample time → injection time) p50/p95 per window. **This is the number
  the PRD question needs; it does not exist yet.**
- Structured errors (the `--ble` dependency error already is) — keep that
  idiom everywhere.

## Test plan & acceptance

- **Unit (Swift):** filter math (still-tremor, fast-motion lag, reconnect
  dt gap), frame encode; BLETransport retry-queue semantics. No test target
  exists yet — creating one is a task packet.
- **Cross-language contract:** encode in Swift (`MacForwarder.encode`) →
  decode in Python (`parse_frame`) golden-file round-trip, both directions
  of change break it. Cheapest high-value test in the repo.
- **Integration (Mac, no hardware):** feed recorded frame captures over UDP
  loopback → assert PointerState trajectory. Enables filter tuning offline.
- **Manual acceptance matrix (device):** BLE and relay transports ×
  {external display, clamshell, permission freshly revoked, out-of-range →
  return, watch wrist-down → wake}. Pass = reconnect without cursor jump,
  click still lands, pill truthful.
- **Standing benchmark:** the 50×50 px / 2 s / 9-of-10 target-click test,
  measured, logged per release.

## Model delegation (this project)

Per the pinned snapshot's `ROLES.md`. Swift bake-off: **pending** — tasks
in the snapshot's `bakeoff/` are grounded in this repo. Until it runs: any
capable non-implementer reviews correctness (Sol default) — in practice:
Grok 4.5 implements only bounded packets with Sol-written criteria; Fable
integration-reviews; Ben runs on hardware (the only oracle with a wrist).

## Project-specific checklist rows (append at review/release)

- [ ] Tested in clamshell mode driving the external display
- [ ] Tested on BLE **and** iPhone-relay transports
- [ ] Accessibility permission revoked/re-granted mid-session recovers
- [ ] Latency p95 measured and logged (no release without the number)
- [ ] Watch battery: session drain noted (15 Hz budget respected)
