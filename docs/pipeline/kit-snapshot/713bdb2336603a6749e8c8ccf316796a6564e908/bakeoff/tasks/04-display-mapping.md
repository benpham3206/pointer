# Bake-off task 04 — Display mapping

Provide with: the display-selection portion of `tools/mac_pointer_server.py`
(`--display external`) and `pointer Mac/MacContentView.swift` if it exposes
display choice.

---

Context: the Mac may have multiple displays, the target is usually an
external monitor, and the MacBook lid may be closed (clamshell) — meaning
the built-in display can appear and disappear at runtime.

Task: write the macOS code that, given multiple displays, external monitor,
and clamshell mode, safely clamps and maps cursor movement to the active
display's bounds. Requirements:

1. Correct handling of macOS's global coordinate space: displays have
   arbitrary origins (negative coordinates exist), and NSScreen vs CGDisplay
   Y-axis conventions differ — be explicit about which you use where.
2. Select the target display by policy (external-preferred, fallback to
   main) and re-evaluate on `CGDisplay` reconfiguration callbacks — lid
   close/open, cable unplug, resolution change.
3. Cursor never strands on a display that just disappeared: name the
   reconfiguration callback you handle
   (`CGDisplayRegisterReconfigurationCallback` / NSScreen notification),
   and guarantee that the **first injected delta after that callback
   fires** places the cursor inside the fallback display's bounds. State
   how a test observes this (post-injection position read-back).
4. Clamp includes menu-bar/dock-safe full frame (document your choice of
   frame vs visibleFrame and why).
5. No polling; configuration changes are event-driven.

Deliver: code + a table of the reconfiguration scenarios (clamshell close,
clamshell open, unplug external, resolution change) with the expected cursor
behavior in each, and how each was or could be verified.
