#!/usr/bin/env python3
"""One-process Mac demo: TCP listener + simulated Watch IMU + live dashboard.

  python3 tools/sensor_demo_mac.py

No Watch or iPhone required. For real hardware see docs/SENSOR_TRACKER.md.
"""

from __future__ import annotations

import argparse
import json
import math
import socket
import sys
import threading
import time
from typing import Any

DEFAULT_PORT = 19778


def fmt(v: float) -> str:
    return f"{v:+.4f}"


def format_line(d: dict[str, Any]) -> str:
    base = (
        f"roll:{fmt(d['roll'])} pitch:{fmt(d['pitch'])} yaw:{fmt(d['yaw'])} | "
        f"ax:{fmt(d['ax'])} ay:{fmt(d['ay'])} az:{fmt(d['az'])} | "
        f"gx:{fmt(d['gx'])} gy:{fmt(d['gy'])} gz:{fmt(d['gz'])}"
    )
    if "relativeAltitudeM" in d:
        base += f" | alt_m:{d['relativeAltitudeM']:+.3f}"
    if "pressureKPa" in d:
        base += f" kPa:{d['pressureKPa']:.3f}"
    return base


def sample(t: float) -> dict[str, float]:
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
        "relativeAltitudeM": math.sin(t * 0.3) * 2.0,
        "pressureKPa": 99.0 + math.sin(t * 0.2) * 0.5,
    }


def run_server(host: str, port: int, out_queue: list[dict[str, Any]], stop: threading.Event) -> None:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as srv:
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind((host, port))
        srv.listen(1)
        srv.settimeout(0.5)
        conn: socket.socket | None = None
        buf = ""
        while not stop.is_set():
            if conn is None:
                try:
                    conn, _ = srv.accept()
                    conn.settimeout(0.2)
                except TimeoutError:
                    continue
                except OSError:
                    break
                continue
            try:
                chunk = conn.recv(4096)
                if not chunk:
                    conn.close()
                    conn = None
                    buf = ""
                    continue
                buf += chunk.decode("utf-8", errors="replace")
                while "\n" in buf:
                    line, buf = buf.split("\n", 1)
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        out_queue.append(json.loads(line))
                    except json.JSONDecodeError:
                        pass
            except TimeoutError:
                continue
            except OSError:
                conn = None
        if conn:
            conn.close()


def main() -> int:
    p = argparse.ArgumentParser(description="Mac-only sensor tracker demo")
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=DEFAULT_PORT)
    p.add_argument("--hz", type=float, default=30.0)
    args = p.parse_args()

    stop = threading.Event()
    queue: list[dict[str, Any]] = []
    threading.Thread(target=run_server, args=(args.host, args.port, queue, stop), daemon=True).start()
    time.sleep(0.15)

    interval = 1.0 / max(args.hz, 1.0)
    phase = 0.0
    sent = 0
    received = 0
    t0 = time.monotonic()
    last_ui = t0

    print(f"sensor_demo_mac: sim → {args.host}:{args.port} @ {args.hz:.0f} Hz (Ctrl-C to quit)")
    print("Source: SIMULATED (same waveform as Watch Simulator)")

    sock: socket.socket | None = None
    for _ in range(40):
        try:
            sock = socket.create_connection((args.host, args.port), timeout=0.25)
            break
        except OSError:
            time.sleep(0.05)
    if sock is None:
        print("Could not connect to local listener", file=sys.stderr)
        return 1

    with sock:
        while True:
            phase += 0.12
            payload = sample(phase)
            sock.sendall((json.dumps(payload) + "\n").encode())
            sent += 1

            while queue:
                d = queue.pop(0)
                received += 1
                now = time.monotonic()
                if now - last_ui >= 0.08:
                    hz = received / max(now - t0, 0.001)
                    sys.stdout.write(
                        f"\r[{received}] ~{hz:.0f} Hz | {format_line(d)}    "
                    )
                    sys.stdout.flush()
                    last_ui = now

            time.sleep(interval)

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("\nStopped.", file=sys.stderr)
        raise SystemExit(0)