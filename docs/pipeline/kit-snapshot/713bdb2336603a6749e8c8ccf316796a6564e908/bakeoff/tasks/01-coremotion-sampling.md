# Bake-off task 01 — CoreMotion sampling

Provide with: `pointer Watch App/MotionManager.swift`,
`Shared/MotionPayload.swift`.

---

Context: a watchOS app streams IMU attitude/rotation-rate to a Mac for
cursor control. The existing `MotionManager` samples `CMDeviceMotion` at
15 Hz with an adaptive EMA filter.

Task: write a watchOS `MotionSampler` (or minimally refactor the provided
`MotionManager`) that streams timestamped `CMDeviceMotion` attitude +
rotation-rate packets safely. Requirements:

1. Use the motion sample's own timestamp, not arrival time; expose it in
   the packet so downstream can detect stale/late data.
2. Correct Swift concurrency: sampling off the main thread, UI-observable
   state published on the main actor, no leaked tasks when tracking stops.
3. Handle: motion unavailable, app backgrounded mid-stream, double
   start/stop calls.
4. Keep the existing 15 Hz battery budget and adaptive-EMA behavior intact.
5. State every assumption about the reference frame you chose and why.

Deliver: code + the test or instrumentation that proves, over a **60-second
foreground run on a physical watch (state the watchOS version)**:
(a) sample timestamps strictly monotonic; (b) sample count ≥ 855 (15 Hz ×
60 s − 5%); (c) no inter-sample gap > 500 ms while foregrounded. CoreMotion
may drop samples — the metric is the receiver-visible stream, not a promise
of zero drops. Background continuity is out of scope and must not be
claimed unless the chosen runtime mode actually supports it (say which).
