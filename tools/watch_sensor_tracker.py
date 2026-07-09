#!/usr/bin/env python3
"""Live Apple Watch IMU viewer (via iPhone TCP mirror).

Usage:
  python3 tools/watch_sensor_tracker.py --live
  python3 tools/watch_sensor_tracker.py --self-test
"""

from __future__ import annotations

import argparse
import json
import socket
import sys
import time
from datetime import datetime

DEFAULT_PORT = 19778
FIELDS = ("roll", "pitch", "yaw", "ax", "ay", "az", "gx", "gy", "gz")


def format_row(data: dict) -> str:
    parts = [f"{k}:{float(data.get(k, 0)):+8.4f}" for k in FIELDS]
    if "relativeAltitudeM" in data:
        parts.append(f"alt_m:{float(data['relativeAltitudeM']):+8.3f}")
    if "pressureKPa" in data:
        parts.append(f"kPa:{float(data['pressureKPa']):8.3f}")
    return " | ".join(parts)


def format_live(data: dict, count: int, hz: float) -> str:
    return f"[n={count} ~{hz:.0f}Hz] {format_row(data)}"


def self_test() -> int:
    sample = {
        "roll": 0.1,
        "pitch": -0.2,
        "yaw": 1.5,
        "ax": 0.01,
        "ay": -0.02,
        "az": 0.98,
        "gx": 0.001,
        "gy": 0.0,
        "gz": -0.003,
    }
    line = json.dumps(sample) + "\n"
    buf = line.encode()
    parsed = json.loads(buf.decode().strip())
    assert all(k in parsed for k in FIELDS)
    print("self-test OK:", format_row(parsed))
    return 0


def handle_client(conn: socket.socket, addr, live: bool) -> None:
    print(f"[{datetime.now().isoformat(timespec='seconds')}] client {addr[0]}:{addr[1]}")
    buf = b""
    count = 0
    t0 = time.monotonic()
    try:
        while True:
            chunk = conn.recv(4096)
            if not chunk:
                break
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                line = line.strip()
                if not line:
                    continue
                try:
                    data = json.loads(line.decode("utf-8"))
                except (json.JSONDecodeError, UnicodeDecodeError) as e:
                    print(f"  bad json: {e}", file=sys.stderr)
                    continue
                count += 1
                elapsed = max(time.monotonic() - t0, 1e-6)
                hz = count / elapsed
                if live:
                    sys.stdout.write("\r" + format_live(data, count, hz)[:200].ljust(200))
                    sys.stdout.flush()
                elif count == 1 or count % 30 == 0:
                    print(format_row(data))
    finally:
        if live:
            print()
        conn.close()
        print(f"  disconnected ({count} samples)")


def main() -> int:
    parser = argparse.ArgumentParser(description="Watch IMU TCP tracker")
    parser.add_argument("--host", default="0.0.0.0", help="bind address")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--live", action="store_true", help="single-line terminal dashboard")
    parser.add_argument("--self-test", action="store_true", help="parse smoke test (no network)")
    args = parser.parse_args()

    if args.self_test:
        return self_test()

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as srv:
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind((args.host, args.port))
        srv.listen(5)
        mode = "live dashboard" if args.live else "sampled lines (every 30)"
        print(f"Listening on {args.host}:{args.port} ({mode})")
        print("Enable iPhone: Python tracker → Mac IP → Stream TCP :19778")
        while True:
            conn, addr = srv.accept()
            handle_client(conn, addr, live=args.live)


if __name__ == "__main__":
    raise SystemExit(main())