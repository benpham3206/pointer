#!/usr/bin/env python3
"""Bonjour TCP: Watch/iPhone → Mac cursor with 4-corner attitude calibration.

JSON lines:
  motion: {roll,yaw,pitch,...}
  click:  {type:click} or {click:1}
  reset:  {type:reset}  — clear origin-only mode (not calib)
  calib:  {type:calib, corner:tl|tr|bl|br, roll,yaw,pitch}
  calib_clear: {type:calib_clear}

After 4 corners, maps Δrad (roll/yaw/pitch) → pixels via affine fit:
  [x y] proportional to attitude within the calibrated pose span
  and the physical monitor size.

Usage:
  python3 tools/mac_pointer_server.py --display external --sensitivity 0.45
"""
from __future__ import annotations

import argparse
import json
import math
import signal
import socket
import subprocess
import sys
import threading
import time
from ctypes import CDLL, POINTER, Structure, byref, c_bool, c_double, c_int32, c_uint32, c_void_p
from ctypes.util import find_library
from pathlib import Path

# --- CoreGraphics ---

class CGPoint(Structure):
    _fields_ = [("x", c_double), ("y", c_double)]


class CGSize(Structure):
    _fields_ = [("width", c_double), ("height", c_double)]


class CGRect(Structure):
    _fields_ = [("origin", CGPoint), ("size", CGSize)]


Quartz = CDLL(find_library("CoreGraphics") or "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
ApplicationServices = CDLL(
    find_library("ApplicationServices")
    or "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"
)
AXIsProcessTrusted = ApplicationServices.AXIsProcessTrusted
AXIsProcessTrusted.restype = c_bool

CGEventCreateMouseEvent = Quartz.CGEventCreateMouseEvent
CGEventCreateMouseEvent.restype = c_void_p
CGEventCreateMouseEvent.argtypes = [c_void_p, c_uint32, CGPoint, c_uint32]
CGEventPost = Quartz.CGEventPost
CGEventPost.argtypes = [c_uint32, c_void_p]
CGEventSourceCreate = Quartz.CGEventSourceCreate
CGEventSourceCreate.restype = c_void_p
CGEventSourceCreate.argtypes = [c_int32]
CGEventCreate = Quartz.CGEventCreate
CGEventCreate.restype = c_void_p
CGEventCreate.argtypes = [c_void_p]
CGEventGetLocation = Quartz.CGEventGetLocation
CGEventGetLocation.restype = CGPoint
CGEventGetLocation.argtypes = [c_void_p]
CGGetActiveDisplayList = Quartz.CGGetActiveDisplayList
CGGetActiveDisplayList.argtypes = [c_uint32, POINTER(c_uint32), POINTER(c_uint32)]
CGGetActiveDisplayList.restype = c_int32
CGDisplayBounds = Quartz.CGDisplayBounds
CGDisplayBounds.argtypes = [c_uint32]
CGDisplayBounds.restype = CGRect
CGMainDisplayID = Quartz.CGMainDisplayID
CGMainDisplayID.restype = c_uint32

CFRelease = CDLL(
    find_library("CoreFoundation") or "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"
).CFRelease
CFRelease.argtypes = [c_void_p]

kCGEventMouseMoved = 5
kCGEventLeftMouseDown = 1
kCGEventLeftMouseUp = 2
kCGMouseButtonLeft = 0
kCGHIDEventTap = 0
kCGEventSourceStateHIDSystemState = 1

CORNERS = ("tl", "tr", "br", "bl")  # clockwise from top-left
SCREEN_UV = {
    "tl": (0.0, 0.0),
    "tr": (1.0, 0.0),
    "br": (1.0, 1.0),
    "bl": (0.0, 1.0),
}

_last_failure_emit: dict[str, float] = {}


def failure_payload(component: str, root_cause: str, failure_type: str) -> dict:
    return {
        "component": component,
        "rootCause": root_cause,
        "failureType": failure_type,
    }


def emit_failure(payload: dict, min_interval: float = 2.0) -> None:
    key = f"{payload.get('component')}:{payload.get('failureType')}:{payload.get('rootCause')}"
    now = time.monotonic()
    if now - _last_failure_emit.get(key, 0.0) < min_interval:
        return
    _last_failure_emit[key] = now
    print("failure " + json.dumps(payload, sort_keys=True), flush=True)


def accessibility_failure(component: str) -> dict | None:
    if AXIsProcessTrusted():
        return None
    return failure_payload(
        component,
        "macOS Accessibility trust is not granted for the Python process running mac_pointer_server.py",
        "permissionDenied",
    )


def list_displays() -> list[dict]:
    ids = (c_uint32 * 16)()
    n = c_uint32(0)
    CGGetActiveDisplayList(16, ids, byref(n))
    main = CGMainDisplayID()
    out = []
    for i in range(n.value):
        did = ids[i]
        r = CGDisplayBounds(did)
        out.append(
            {
                "id": did,
                "main": did == main,
                "x": r.origin.x,
                "y": r.origin.y,
                "w": r.size.width,
                "h": r.size.height,
                "area": r.size.width * r.size.height,
            }
        )
    return out


def pick_display(mode: str) -> dict:
    displays = list_displays()
    if not displays:
        return {"id": 0, "main": True, "x": 0, "y": 0, "w": 1920, "h": 1080, "area": 0}
    if mode == "main":
        return next((d for d in displays if d["main"]), displays[0])
    if mode == "largest":
        return max(displays, key=lambda d: d["area"])
    # external (default): non-main if any, else largest
    non_main = [d for d in displays if not d["main"]]
    if non_main:
        return max(non_main, key=lambda d: d["area"])
    return max(displays, key=lambda d: d["area"])


def mouse_move(x: float, y: float) -> None:
    if failure := accessibility_failure("mac_pointer_server.mouse_move"):
        emit_failure(failure)
        return
    pt = CGPoint(x, y)
    ev = CGEventCreateMouseEvent(None, kCGEventMouseMoved, pt, kCGMouseButtonLeft)
    if not ev:
        emit_failure(
            failure_payload(
                "mac_pointer_server.mouse_move",
                "CoreGraphics did not create a mouse moved event",
                "eventCreationFailed",
            )
        )
        return
    CGEventPost(kCGHIDEventTap, ev)
    CFRelease(ev)


def left_click() -> dict | None:
    if failure := accessibility_failure("mac_pointer_server.left_click"):
        emit_failure(failure, min_interval=0.25)
        return failure
    ev = CGEventCreate(None)
    if not ev:
        failure = failure_payload(
            "mac_pointer_server.left_click",
            "CoreGraphics did not return the current cursor event",
            "unavailableResource",
        )
        emit_failure(failure)
        return failure
    loc = CGEventGetLocation(ev)
    CFRelease(ev)
    src = CGEventSourceCreate(kCGEventSourceStateHIDSystemState)
    pt = CGPoint(loc.x, loc.y)
    down = CGEventCreateMouseEvent(src, kCGEventLeftMouseDown, pt, kCGMouseButtonLeft)
    up = CGEventCreateMouseEvent(src, kCGEventLeftMouseUp, pt, kCGMouseButtonLeft)
    if not down or not up:
        failure = failure_payload(
            "mac_pointer_server.left_click",
            "CoreGraphics did not create left mouse down/up events",
            "eventCreationFailed",
        )
        emit_failure(failure)
        if down:
            CFRelease(down)
        if up:
            CFRelease(up)
        if src:
            CFRelease(src)
        return failure
    CGEventPost(kCGHIDEventTap, down)
    CFRelease(down)
    time.sleep(0.008)
    CGEventPost(kCGHIDEventTap, up)
    CFRelease(up)
    if src:
        CFRelease(src)
    print(f"click @ ({loc.x:.0f},{loc.y:.0f})", flush=True)
    return None


def _solve_linear(a: list[list[float]], b: list[float]) -> list[float] | None:
    """Gaussian elimination with partial pivot. a is n×n, b length n."""
    n = len(b)
    m = [row[:] + [b[i]] for i, row in enumerate(a)]
    for col in range(n):
        pivot = max(range(col, n), key=lambda r: abs(m[r][col]))
        if abs(m[pivot][col]) < 1e-12:
            return None
        m[col], m[pivot] = m[pivot], m[col]
        div = m[col][col]
        for j in range(col, n + 1):
            m[col][j] /= div
        for r in range(n):
            if r == col:
                continue
            factor = m[r][col]
            for j in range(col, n + 1):
                m[r][j] -= factor * m[col][j]
    return [m[i][n] for i in range(n)]


def fit_affine_3d(samples: list[tuple[float, float, float, float, float]]) -> tuple[list[float], list[float]] | None:
    """Least squares: x,y = f(roll,yaw,pitch,1). samples: (r,y,p,sx,sy).

    If pitch has near-zero variance (common), fit roll/yaw only and set pitch coef=0.
    """
    pitches = [s[2] for s in samples]
    pvar = max(pitches) - min(pitches)
    use_pitch = pvar > 1e-4

    def fit_cols(cols: list[int]) -> tuple[list[float], list[float]] | None:
        n = len(cols)
        ata = [[0.0] * n for _ in range(n)]
        atx = [0.0] * n
        aty = [0.0] * n
        for r, yw, p, sx, sy in samples:
            full = [r, yw, p, 1.0]
            row = [full[i] for i in cols]
            for i in range(n):
                atx[i] += row[i] * sx
                aty[i] += row[i] * sy
                for j in range(n):
                    ata[i][j] += row[i] * row[j]
        # ridge for stability
        for i in range(n):
            ata[i][i] += 1e-9
        cx = _solve_linear([row[:] for row in ata], atx[:])
        cy = _solve_linear([row[:] for row in ata], aty[:])
        if cx is None or cy is None:
            return None
        return cx, cy

    if use_pitch:
        got = fit_cols([0, 1, 2, 3])
        if got:
            return got
    # roll, yaw, 1 → expand to 4 coeffs with pitch=0
    got = fit_cols([0, 1, 3])
    if not got:
        # last resort: yaw, roll only without bias fail — try yaw+bias / roll+bias separately impossible for 2D
        got = fit_cols([0, 1, 3])
        if not got:
            return None
    cx3, cy3 = got
    # map [r,y,1] -> [r,y,p,1]
    cx = [cx3[0], cx3[1], 0.0, cx3[2]]
    cy = [cy3[0], cy3[1], 0.0, cy3[2]]
    return cx, cy


class PointerState:
    def __init__(self, sensitivity: float, display: dict, calib_path: Path):
        self.sensitivity = sensitivity  # scales calibrated map (1.0 = exact fit)
        self.display = display
        self.x0 = display["x"]
        self.y0 = display["y"]
        self.w = display["w"]
        self.h = display["h"]
        self.calib_path = calib_path
        # corner -> (roll, yaw, pitch)
        self.corners: dict[str, tuple[float, float, float]] = {}
        # affine coeffs for x and y: [a,b,c,d] * [roll,yaw,pitch,1]
        self.coeff_x: list[float] | None = None
        self.coeff_y: list[float] | None = None
        # fallback origin mode
        self.origin: tuple[float, float, float] | None = None
        self.load_calib()
        print(
            f"display id={display['id']} main={display['main']} "
            f"origin=({self.x0:.0f},{self.y0:.0f}) size={self.w:.0f}x{self.h:.0f} "
            f"calib={'yes' if self.coeff_x else 'no'}",
            flush=True,
        )

    def load_calib(self) -> None:
        if not self.calib_path.exists():
            return
        try:
            data = json.loads(self.calib_path.read_text())
            raw = data.get("corners") or {}
            for k, v in raw.items():
                if k in CORNERS and len(v) >= 3:
                    self.corners[k] = (float(v[0]), float(v[1]), float(v[2]))
            self.rebuild_map()
            print(f"loaded calib {self.calib_path} corners={list(self.corners)}", flush=True)
        except Exception as e:
            print(f"calib load failed: {e}", flush=True)

    def save_calib(self) -> None:
        payload = {
            "corners": {k: list(v) for k, v in self.corners.items()},
            "display": self.display,
        }
        self.calib_path.parent.mkdir(parents=True, exist_ok=True)
        self.calib_path.write_text(json.dumps(payload, indent=2))
        print(f"saved calib → {self.calib_path}", flush=True)

    def clear_calib(self) -> None:
        self.corners.clear()
        self.coeff_x = self.coeff_y = None
        self.origin = None
        if self.calib_path.exists():
            self.calib_path.unlink()
        print("calib cleared", flush=True)

    def set_corner(self, corner: str, roll: float, yaw: float, pitch: float) -> None:
        corner = corner.lower().strip()
        if corner not in CORNERS:
            print(f"bad corner {corner}", flush=True)
            return
        self.corners[corner] = (roll, yaw, pitch)
        print(f"calib {corner}: roll={roll:.4f} yaw={yaw:.4f} pitch={pitch:.4f}", flush=True)
        # Move cursor to that screen corner as feedback
        u, v = SCREEN_UV[corner]
        mouse_move(self.x0 + u * (self.w - 1), self.y0 + v * (self.h - 1))
        if len(self.corners) == 4:
            self.rebuild_map()
            self.save_calib()
        else:
            missing = [c for c in CORNERS if c not in self.corners]
            print(f"calib progress {len(self.corners)}/4 missing={missing}", flush=True)

    def rebuild_map(self) -> None:
        if len(self.corners) < 4:
            self.coeff_x = self.coeff_y = None
            return
        samples = []
        for name, (r, yw, p) in self.corners.items():
            u, v = SCREEN_UV[name]
            sx = self.x0 + u * (self.w - 1)
            sy = self.y0 + v * (self.h - 1)
            samples.append((r, yw, p, sx, sy))
        fit = fit_affine_3d(samples)
        if not fit:
            print("calib fit failed — check distinct corner poses", flush=True)
            self.coeff_x = self.coeff_y = None
            return
        self.coeff_x, self.coeff_y = fit
        # Report rad→pixel scale (proportional to monitor size by construction)
        print(
            f"calib ready  x≈ {self.coeff_x[0]:.1f}*roll + {self.coeff_x[1]:.1f}*yaw + {self.coeff_x[2]:.1f}*pitch + {self.coeff_x[3]:.1f}",
            flush=True,
        )
        print(
            f"             y≈ {self.coeff_y[0]:.1f}*roll + {self.coeff_y[1]:.1f}*yaw + {self.coeff_y[2]:.1f}*pitch + {self.coeff_y[3]:.1f}",
            flush=True,
        )
        # Span diagnostics
        yaws = [c[1] for c in self.corners.values()]
        rolls = [c[0] for c in self.corners.values()]
        dy = max(yaws) - min(yaws)
        dr = max(rolls) - min(rolls)
        if dy > 1e-6:
            print(f"  yaw span {dy:.4f} rad → {self.w:.0f}px  ({self.w/dy:.0f} px/rad)", flush=True)
        if dr > 1e-6:
            print(f"  roll span {dr:.4f} rad → {self.h:.0f}px  ({self.h/dr:.0f} px/rad)", flush=True)

    def reset_origin(self) -> None:
        self.origin = None
        print("origin reset (fallback mode)", flush=True)

    def handle(self, obj: dict) -> None:
        t = obj.get("type")
        if t == "calib_clear":
            self.clear_calib()
            return
        if t == "calib":
            corner = str(obj.get("corner", ""))
            try:
                r = float(obj["roll"])
                yw = float(obj["yaw"])
                p = float(obj.get("pitch", 0.0))
            except (KeyError, TypeError, ValueError):
                print("calib missing roll/yaw", flush=True)
                return
            self.set_corner(corner, r, yw, p)
            return
        if t == "reset":
            self.reset_origin()
            return
        if t == "click" or bool(obj.get("click")):
            left_click()

        if "roll" not in obj or "yaw" not in obj:
            return
        try:
            roll = float(obj["roll"])
            yaw = float(obj["yaw"])
            pitch = float(obj.get("pitch", 0.0))
        except (TypeError, ValueError):
            return

        if self.coeff_x and self.coeff_y:
            self._move_calibrated(roll, yaw, pitch)
        else:
            self._move_fallback(roll, yaw, pitch)

    def _move_calibrated(self, roll: float, yaw: float, pitch: float) -> None:
        assert self.coeff_x and self.coeff_y
        cx, cy = self.coeff_x, self.coeff_y
        # Affine already spans monitor corners; sensitivity scales around center.
        x = cx[0] * roll + cx[1] * yaw + cx[2] * pitch + cx[3]
        y = cy[0] * roll + cy[1] * yaw + cy[2] * pitch + cy[3]
        if self.sensitivity != 1.0:
            mid_x = self.x0 + self.w / 2
            mid_y = self.y0 + self.h / 2
            x = mid_x + (x - mid_x) * self.sensitivity
            y = mid_y + (y - mid_y) * self.sensitivity
        x = max(self.x0, min(self.x0 + self.w - 1, x))
        y = max(self.y0, min(self.y0 + self.h - 1, y))
        mouse_move(x, y)

    def _move_fallback(self, roll: float, yaw: float, pitch: float) -> None:
        # Uncalibrated: origin + rad * (monitor_dim / typical_span)
        # Default assume ~0.6 rad full sweep across display unless sensitivity overrides.
        if self.origin is None:
            self.origin = (roll, yaw, pitch)
            print(f"origin set r={roll:.3f} y={yaw:.3f} p={pitch:.3f} (uncalibrated)", flush=True)
            return
        or_, oy, op = self.origin
        # px per radian so ~0.5 rad covers full width/height at sens=1
        sx = self.w / 0.5
        sy = self.h / 0.5
        s = self.sensitivity if self.sensitivity != 1.0 else 1.0
        # Use yaw→X, roll→Y; pitch adds to Y slightly
        x = self.x0 + self.w / 2 + (yaw - oy) * sx * s
        y = self.y0 + self.h / 2 - (roll - or_) * sy * s - (pitch - op) * sy * 0.3 * s
        x = max(self.x0, min(self.x0 + self.w - 1, x))
        y = max(self.y0, min(self.y0 + self.h - 1, y))
        mouse_move(x, y)


def handle_client(conn: socket.socket, addr, state: PointerState) -> None:
    print(f"client {addr}", flush=True)
    buf = b""
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
                    obj = json.loads(line.decode("utf-8"))
                except json.JSONDecodeError:
                    continue
                if isinstance(obj, dict):
                    state.handle(obj)
    finally:
        conn.close()
        print(f"client closed {addr}", flush=True)


def register_bonjour(port: int) -> subprocess.Popen | None:
    try:
        proc = subprocess.Popen(
            ["dns-sd", "-R", "pointer", "_pointer._tcp", "local", str(port)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        print(f"bonjour: pointer._pointer._tcp local:{port} (pid {proc.pid})", flush=True)
        return proc
    except FileNotFoundError:
        return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--port", type=int, default=19790)
    ap.add_argument(
        "--sensitivity",
        type=float,
        default=0.45,
        help="Scale factor on calibrated map (1=exact corner fit). Uncalibrated: scales px/rad.",
    )
    ap.add_argument("--display", choices=("external", "main", "largest"), default="external")
    ap.add_argument(
        "--calib-file",
        type=Path,
        default=Path.home() / ".hermes" / "pointer-calib.json",
    )
    args = ap.parse_args()

    print("active displays:", flush=True)
    for d in list_displays():
        print(f"  {d}", flush=True)
    if failure := accessibility_failure("mac_pointer_server.startup"):
        emit_failure(failure, min_interval=0.0)
    display = pick_display(args.display)
    state = PointerState(args.sensitivity, display, args.calib_file)
    bonjour = register_bonjour(args.port)

    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("0.0.0.0", args.port))
    sock.listen(8)
    print(f"listening TCP :{args.port}", flush=True)
    print("Calibrate: point Watch at TL→TR→BR→BL, capture each corner.", flush=True)

    def shutdown(*_):
        print("shutdown", flush=True)
        if bonjour:
            bonjour.terminate()
        try:
            sock.close()
        except Exception:
            pass
        sys.exit(0)

    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)

    while True:
        conn, addr = sock.accept()
        threading.Thread(target=handle_client, args=(conn, addr, state), daemon=True).start()


if __name__ == "__main__":
    raise SystemExit(main())
