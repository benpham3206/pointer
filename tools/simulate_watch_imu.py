#!/usr/bin/env python3
"""Fake Watch IMU stream into watch_sensor_tracker.py (Mac-only demo).

Terminal 1:
  python3 tools/watch_sensor_tracker.py --live

Terminal 2:
  python3 tools/simulate_watch_imu.py --host 127.0.0.1
"""

from __future__ import annotations

import argparse
import json
import math
import socket
import sys
import time

DEFAULT_PORT = 19778


def sample(t: float) -> dict:
    return {
        "roll": math.sin(t) * 0.4,
        "pitch": math.cos(t * 0.7) * 0.3,
        "yaw": t % (2 * math.pi),
        "ax": math.sin(t * 2) * 0.05,
        "ay": math.cos(t * 2) * 0.05,
        "az": 0.98 + math.sin(t) * 0.02,
        "gx": math.sin(t) * 0.02,
        "gy": math.cos(t) * 0.02,
        "gz": math.sin(t * 0.5) * 0.01,
    }


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=DEFAULT_PORT)
    p.add_argument("--hz", type=float, default=30.0)
    p.add_argument("--seconds", type=float, default=0, help="0 = run until Ctrl-C")
    args = p.parse_args()

    interval = 1.0 / max(args.hz, 1.0)
    t0 = time.monotonic()
    phase = 0.0
    sent = 0

    with socket.create_connection((args.host, args.port), timeout=5) as sock:
        print(f"Streaming simulated IMU to {args.host}:{args.port} @ {args.hz:.0f} Hz")
        while True:
            phase += 0.12
            line = json.dumps(sample(phase)) + "\n"
            sock.sendall(line.encode())
            sent += 1
            if args.seconds > 0 and (time.monotonic() - t0) >= args.seconds:
                break
            time.sleep(interval)

    print(f"Sent {sent} samples")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("\nStopped", file=sys.stderr)
        raise SystemExit(0)