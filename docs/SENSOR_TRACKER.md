# Sensor tracker prototype

See live **Apple Watch** `CMMotionManager` device motion on **Xcode (Watch + iPhone)** or **Python on your Mac**.

## Mac-only demo (no Watch)

**One command:**

```bash
cd ~/Projects/pointer
python3 tools/sensor_demo_mac.py
```

Or two terminals (same as iPhone TCP path):

```bash
# terminal 1
python3 tools/watch_sensor_tracker.py --live

# terminal 2
python3 tools/simulate_watch_imu.py --host 127.0.0.1
```

Watch **Simulator** uses the same synthetic waveform in-app (purple **SIM** pill) so Xcode UI + console logs work without a device.

## Xcode (recommended first)

1. Open `pointer.xcodeproj`, select scheme **pointer Watch App**.
2. Pair a **physical** Watch + iPhone (simulator motion is not real IMU).
3. Run **pointer Watch App** on the watch → **Start tracking**.
4. On the watch you see attitude, user acceleration, gyro, ~Hz, and iPhone reachability.
5. Run **pointer** on the iPhone (companion) — **Live IMU** panel mirrors the last sample.

**Xcode debug:** With **pointer Watch App** running on a device, open the **Watch** scheme console — `IMU` logs (~1 Hz summary + sample every 30 frames) use subsystem `bp.pointer.watch`.

## Python on Mac

1. On Mac:

   ```bash
   cd ~/Projects/pointer
   python3 tools/watch_sensor_tracker.py --self-test   # no hardware
   python3 tools/watch_sensor_tracker.py --live        # rolling terminal dashboard
   ```

2. Find your Mac’s LAN IP (System Settings → Network).
3. On iPhone **pointer** app → **Python tracker** → enter Mac IP → enable **Stream to Mac TCP :19778**.
4. Start tracking on the Watch. Terminal prints JSON lines (~60 Hz; every 30th line printed to avoid spam).

Same JSON keys as `Shared/MotionPayload.swift`: `roll`, `pitch`, `yaw`, `ax`, `ay`, `az`, `gx`, `gy`, `gz`.

## Notes

- Watch → iPhone uses **WCSession** (`sendMessage`); iPhone must be unlocked and app in foreground for best reachability.
- Python path does **not** require the Mac pointer app or Bonjour — only TCP to port **19778**.
- Pointer/cursor relay (`MacForwarder` / `MacMotionReceiver`) is separate; you can use tracker without moving the cursor.

## Optional: plot in Python

Pipe one line to a quick plot script later, or extend `watch_sensor_tracker.py` with `matplotlib` if you want charts (not required for the prototype).
## Watch tap → Mac left-click

1. Mac: run **pointer** (Mac target / Mac app) with Accessibility allowed.
2. iPhone: open **pointer** (connected to Mac via Bonjour).
3. Watch: open app → **Click (left)** or **double-tap** screen.

