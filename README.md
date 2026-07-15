# Pointer

Control a Mac pointer and keyboard from iPhone or Apple Watch.

## Run

1. Launch `/Applications/Pointer Mac.app`.
2. Grant Accessibility permission when prompted.
3. Open Pointer on iPhone or Apple Watch and start tracking.

The Mac menu-bar app listens for Bonjour UDP relay traffic on port `19790`
(`_pointer._udp`) and advertises an in-process BLE peripheral. It calibrates
each source independently, arbitrates phone and Watch input, smooths pointer
motion, and synthesizes cursor and keyboard events.

Use the Python programs under `tools/` only as development and diagnostic
utilities. They are not the normal runtime.

See [docs/SENSOR_TRACKER.md](docs/SENSOR_TRACKER.md) for setup and diagnostics.
