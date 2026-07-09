# Pointer — Roadmap / Backlog

Captured 2026-07-08. Data path today: **Watch → iPhone (`PhoneWatchReceiver`) → `MacForwarder` (Bonjour **UDP**, compact binary frames) → `tools/mac_pointer_server.py` → cursor.**

---

## 1. Smoother tracking (reduce jitter) — ✅ DONE (2026-07-09)
`pointer Watch App/MotionManager.swift`: the fixed EMA is now an **adaptive (One-Euro-lite) EMA** — `attitudeEmaAlpha = 0.08` base (heavy smoothing when nearly still → kills tremor), α ramps with angular speed up to 0.9 (low lag when actually moving). Pairs with the Mac-side dead zone (#2).
_Next if needed:_ a full One-Euro filter, or Mac-side smoothing independent of watch rate.

## 2. Smaller arm movement — ✅ DONE (2026-07-09)
`tools/mac_pointer_server.py`: added a **dynamic acceleration curve** (`--accel`, default 1.5) — gentle gain near center (precise), amplified toward the edges so the calibrated wrist range now reaches the actual screen corners — plus a **dead zone** (`--deadzone`, default 2 px) that suppresses sub-threshold moves. `--sensitivity` is the base gain.
_Next if needed:_ expose gain as a live slider in the watch/phone UI.

## Transport / battery — ✅ DONE (2026-07-09)
Watch IMU + phone send rate lowered to **15 Hz** (`motionHz` in `MotionManager.swift`) for battery. iPhone→Mac leg rewritten from **TCP + JSON lines → UDP + compact binary frames** (`MacForwarder.encode` ↔ `mac_pointer_server.py parse_frame`; type byte + LE float32). A dropped motion frame is harmless; control frames (click/calib/reset) rely on LAN UDP reliability — revisit with seq/ack + dedup if drops become noticeable.

## Direct Watch → Mac BLE transport — ✅ DONE (2026-07-09)
`pointer Watch App/BLETransport.swift` and `tools/mac_ble_peripheral.swift` now
use a custom BLE service with separate motion and control characteristics for
the existing compact frames.
Because watchOS only supports the BLE central role, `tools/mac_ble_peripheral.swift`
advertises the service on the Mac and the Watch writes to it. Once connected,
BLE is the sole Watch transport: motion remains 15 Hz and may drop under
backpressure, while click/calibration/reset frames use acknowledged writes and
queue/retry. Without a connection, `MotionManager` leaves the existing
WCSession → iPhone → Bonjour UDP relay unchanged.

Run `python3 tools/mac_pointer_server.py --display external --ble`. The Watch
auto-scans and reconnects with backoff; the Mac helper forwards exact BLE bytes
to the same UDP socket and therefore the same `parse_frame` → `PointerState`
path. Calibration order, degenerate-spread protection, deadzone, and
acceleration are shared unchanged.

## 3. On-screen "liquid glass" pop-up keyboard (Apple-Glass style)
**Goal:** an Apple/visionOS-style translucent keyboard that pops up for text entry.

**Design questions to settle first:**
- Where is the keyboard **rendered** — on the Mac (pointer clicks the keys) or on the phone/watch (tap the keys)? See #5 — user wants it on **both iPhone and watch**.
- How do keystrokes reach the Mac? The Mac server (`mac_pointer_server.py`) currently only does mouse move + left click. Need a new **`{type:"key", ...}` event** → `CGEventCreateKeyboardEvent` on the Mac.
- "Liquid glass" = iOS/macOS 26 material (`.regularMaterial` / `.ultraThinMaterial`, glass effects).

**New work:** key-event type end-to-end (watch/phone UI → forwarder → server → `CGEventCreateKeyboardEvent`).

## 4. Use the iPhone IMU as a mouse too
**Goal:** point with the phone itself, not only the watch.

**Why it's feasible:** the phone already holds the Mac connection (`MacForwarder`). Add an iOS-side motion source that reuses the same forward path.

**Approach:**
- Add a `CMMotionManager` reader on iOS (mirror of the watch `MotionManager`), gated to a "Use iPhone as pointer" toggle.
- Feed its (EMA-filtered) attitude straight into `macForwarder.forwardMotion(...)` — no watch required.
- Decide arbitration when **both** watch and phone stream (last-writer-wins, or a source selector).

## 5. Liquid-glass keyboard on BOTH iPhone and watch
**Goal:** the #3 keyboard is available on iPhone and watch, each sending keystrokes to the Mac.

**Depends on #3** (the `key` event type + Mac `CGEventCreateKeyboardEvent`). Then build:
- iOS keyboard view (full glass keyboard).
- watchOS keyboard view (compact — scribble/grid or key strip given the small screen).
- Both route through the existing control path (`sendControl` on watch, `MacForwarder` on phone).

---

### Suggested order
✅ 1 + 2 (smoothing + gain) and UDP/battery transport are done. **Next:** 4 (phone as pointer, reuses the forward path) → 3 + 5 (keyboard: Mac `CGEventCreateKeyboardEvent` support, then iOS glass UI, then watch UI).
