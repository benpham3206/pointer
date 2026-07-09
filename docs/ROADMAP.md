# Pointer — Roadmap / Backlog

Captured 2026-07-08. Not yet implemented — planning notes for the next work session.
Data path today: **Watch → iPhone (`PhoneWatchReceiver`) → `MacForwarder` (Bonjour TCP) → `tools/mac_pointer_server.py` → cursor.**

---

## 1. Smoother tracking (reduce jitter)
**Goal:** the cursor should feel steady, not jittery.

**Where it lives now:** `pointer Watch App/MotionManager.swift` — EMA low-pass on attitude, `attitudeEmaAlpha = 0.15` (angle-wrap aware). Mac side does no smoothing.

**Ideas to try:**
- Replace/augment the plain EMA with a **One-Euro filter** (the standard for pointing devices: low lag when moving fast, heavy smoothing when slow). Best bang-for-buck.
- Add a small **dead zone** so micro-tremor below a threshold produces no cursor motion.
- Smooth on the **Mac side too** (`_move_calibrated` / `_move_fallback` in `mac_pointer_server.py`) so it's independent of watch sample rate.
- Consider raising the watch sample rate (currently 20 Hz) if battery allows.

**Open question:** tune the existing EMA α first (cheap) vs. jump to One-Euro (better, more code)?

## 2. Smaller arm movement
**Goal:** cover the whole screen with less physical wrist/arm movement.

**Where it lives now:** `mac_pointer_server.py` `--sensitivity` (default 0.45, scales the calibrated map around center); calibrated affine map spans the captured corner poses.

**Ideas to try:**
- Raise the gain / expose sensitivity from the watch or phone UI (live slider).
- Add a **pointer acceleration curve** (small moves = precise, fast moves = cover more) — an exponent on the velocity.
- Calibrate with intentionally smaller corner angles so the same screen span maps to less wrist travel.

**Interacts with #1** — higher gain amplifies jitter, so do these together.

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
1 + 2 together (smoothing + gain) → 4 (phone as pointer, reuses path) → 3 + 5 (keyboard: Mac key-event support, then iOS UI, then watch UI).
