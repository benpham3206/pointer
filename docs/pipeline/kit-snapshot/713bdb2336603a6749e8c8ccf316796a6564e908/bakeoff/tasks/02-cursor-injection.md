# Bake-off task 02 — Cursor injection

Provide with: `pointer Mac/CursorAccessibility.swift`,
`Shared/MouseController.swift` (and note the Python alternative
`tools/mac_pointer_server.py` exists — the task is the native Swift path).

---

Context: a Mac app receives relative motion deltas and must move the system
cursor, on a machine that may be in clamshell mode driving an external
display.

Task: write the macOS code that moves the cursor using relative deltas via
`CGEvent`, and handles Accessibility permission failure. Requirements:

1. Check Accessibility trust before injecting; on denial, surface a
   user-visible state and a way to recover after granting — no crash, no
   silent no-op, no permission-prompt loop.
2. Post events correctly (tap location, event source) for the reference
   configuration: MacBook lid closed, one external display active,
   Accessibility granted. Define expected behavior as: injected delta (dx,
   dy) moves the cursor to `clamp(prev + delta, activeDisplayBounds)`, and
   state which API you read the post-move position back with to verify.
3. Clamp to valid display bounds; no cursor teleporting to (0,0) on bad
   input; reject NaN/inf deltas.
4. Include left-click down/up injection with correct click-state handling
   for double-clicks.
5. Instrument: one log line per state transition (permission granted/denied,
   injection started/stopped), none per event.

Deliver: code + a manual test script (steps a human follows in <5 min) that
proves permission-denial recovery works.
