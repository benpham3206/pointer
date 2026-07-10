# Bake-off task 03 — Filter pipeline

Provide with: the filtering portions of `tools/mac_pointer_server.py`
(dead zone, accel curve, sensitivity) and
`pointer Watch App/MotionManager.swift` (adaptive EMA), for reference.

---

Context: IMU-derived cursor deltas need conditioning: tremor suppressed when
nearly still, low lag when moving, reachable screen corners, no runaway
cursor.

Task: implement, in Swift, a self-contained filter pipeline for cursor
deltas: dead zone → low-pass smoothing (One-Euro or adaptive EMA) → gain
curve → max-velocity clamp. Requirements:

1. Pure and testable: `(delta, timestamp) -> delta`, no globals, no I/O.
2. Timestamp-aware: smoothing must use real dt, not assume a fixed rate —
   packets arrive at ~15 Hz with jitter and drops.
3. Parameters in one config struct with the current production defaults
   (dead zone 2 px, base gain 1.5-exponent accel curve) and documented units.
4. Numerically safe: first-sample case, dt = 0, dt huge after a reconnect,
   NaN input.
5. Match the behavior intent of the existing Python implementation; note
   any place you deliberately diverge and why.

Deliver: code + unit tests covering: still-hand tremor suppressed, fast
motion low-lag, corner reachability under the gain curve, reconnect gap
handled without a cursor jump.
