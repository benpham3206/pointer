# Pointer Roadmap

## Shipped

- [x] Replace `tools/mac_pointer_server.py` with the native `Pointer Mac`
  menu-bar app.
- [x] Receive Bonjour UDP on port `19790` (`_pointer._udp`) and host the BLE
  peripheral in-process.
- [x] Support wire protocol message types `0x01` through `0x08`, including
  keyboard synthesis (`0x06`/`0x07`) and source arbitration (`0x08`).
- [x] Calibrate each input source independently with four corners.
- [x] Apply One-Euro filtering and 120 Hz spring smoothing on Mac.
- [x] Relay Watch input through iPhone and support direct BLE transport.
- [x] Use iPhone gyro input as a pointer with a `+Y` world ray and
  corner-agnostic calibration.
- [x] Arbitrate iPhone and Watch pointer sources.
- [x] Send keyboard input from iPhone and Apple Watch.
- [x] Ship the iPhone liquid-glass keyboard slice.
- [x] Keep Watch tracking alive with a workout session.

## Remaining

- [ ] Port Watch pointing from attitude to the ray model after the hardware
  verdict.
- [ ] Complete the manual HealthKit capability, signing, and permission steps.
- [ ] Finish liquid-glass polish across the full UI.
- [ ] Install and verify the Watch app on physical hardware.
