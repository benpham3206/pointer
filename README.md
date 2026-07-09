# pointer

Watch → Mac pointer companion. The Watch uses direct Bluetooth LE when the Mac
server is running with `--ble`; otherwise it automatically keeps the existing
Watch → iPhone → Mac Bonjour/UDP relay.

## Sensor tracker (IMU + barometer)

**Fastest on Mac:**

```bash
python3 tools/mac_pointer_server.py --display external --ble
```

`--ble` is optional and uses the installed Xcode command-line tools to start a
small local CoreBluetooth helper. If that helper is unavailable, the server logs
a structured dependency error and continues serving the UDP relay on port 19790.
Grant the Python process Accessibility permission before sending cursor events.

**Xcode:** Run **pointer Watch App** on a physical Watch → **Start tracking**.
The status pill reads **BLE** once the Mac has connected; otherwise it reads
**iPhone** and uses the relay. The Simulator shows **SIM** and cannot provide a
real BLE peripheral connection.

Full steps: **[docs/SENSOR_TRACKER.md](docs/SENSOR_TRACKER.md)**
