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

## Test the Watch BLE transport

Run `./tests/ble-transport/run.sh` with the macOS Swift toolchain. It compiles `BLETransport.swift` against a local CoreBluetooth test double in a temporary directory and reports each check. It does not test physical Watch behavior or CoreBluetooth scheduling.
