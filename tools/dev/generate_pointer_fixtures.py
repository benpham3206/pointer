#!/usr/bin/env python3
"""Generate deterministic Swift parity fixtures from mac_pointer_server.py."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
REFERENCE = ROOT / "tools" / "mac_pointer_server.py"
OUTPUT = ROOT / "tests" / "fixtures" / "calibration_parity.json"


def load_reference():
    spec = importlib.util.spec_from_file_location("mac_pointer_server", REFERENCE)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import reference module at {REFERENCE}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


DISPLAY = {"x": 120.0, "y": -80.0, "w": 1728.0, "h": 1117.0}
SCENARIOS = [
    {
        "name": "normal",
        "source": "fresh",
        "corners": {
            "tl": [-0.24, -0.31, 0.02],
            "tr": [-0.24, 0.30, 0.02],
            "bl": [0.25, -0.31, 0.02],
            "br": [0.25, 0.30, 0.02],
        },
    },
    {
        "name": "degenerate-spread-rejected",
        "source": "fresh",
        "corners": {
            "tl": [-0.010, -0.015, -0.006],
            "tr": [-0.008, 0.014, 0.005],
            "bl": [0.012, -0.013, 0.007],
            "br": [0.011, 0.015, -0.004],
        },
    },
    {
        "name": "non-axis-aligned",
        "source": "fresh",
        "corners": {
            "tl": [-0.29, -0.21, 0.08],
            "tr": [-0.18, 0.37, -0.04],
            "bl": [0.34, -0.32, 0.13],
            "br": [0.23, 0.29, -0.09],
        },
    },
    {
        "name": "legacy-import",
        "source": "legacy ~/.hermes/pointer-calib.json",
        "corners": {
            "tl": [-0.31, -0.27, 0.01],
            "tr": [-0.20, 0.33, 0.04],
            "bl": [0.28, -0.35, -0.03],
            "br": [0.36, 0.25, 0.02],
        },
    },
]


def pose_at(corners: dict[str, list[float]], u: float, v: float) -> list[float]:
    weights = {
        "tl": (1.0 - u) * (1.0 - v),
        "tr": u * (1.0 - v),
        "bl": (1.0 - u) * v,
        "br": u * v,
    }
    return [sum(weights[name] * corners[name][i] for name in weights) for i in range(3)]


def predict(coefficients: list[float], pose: list[float]) -> float:
    return sum(coefficients[i] * pose[i] for i in range(3)) + coefficients[3]


def main() -> None:
    reference = load_reference()
    cases = []
    points = [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0), (0.5, 0.5), (0.25, 0.75)]
    for scenario in SCENARIOS:
        corners = scenario["corners"]
        samples = []
        for name in reference.CORNERS:
            roll, yaw, pitch = corners[name]
            u, v = reference.SCREEN_UV[name]
            x = DISPLAY["x"] + u * (DISPLAY["w"] - 1.0)
            y = DISPLAY["y"] + v * (DISPLAY["h"] - 1.0)
            samples.append((roll, yaw, pitch, x, y))
        fit = reference.fit_affine_3d(samples)
        if fit is None:
            raise RuntimeError(f"reference fit unexpectedly failed for {scenario['name']}")
        coeff_x, coeff_y = fit
        roll_span = max(value[0] for value in corners.values()) - min(value[0] for value in corners.values())
        yaw_span = max(value[1] for value in corners.values()) - min(value[1] for value in corners.values())
        predictions = []
        for u, v in points:
            pose = pose_at(corners, u, v)
            predictions.append(
                {
                    "uv": [u, v],
                    "pose": pose,
                    "pixel": [predict(coeff_x, pose), predict(coeff_y, pose)],
                }
            )
        case = {
            **scenario,
            "display": DISPLAY,
            "accepted": roll_span >= reference.MIN_CALIB_SPAN and yaw_span >= reference.MIN_CALIB_SPAN,
            "rollSpan": roll_span,
            "yawSpan": yaw_span,
            "coeffX": coeff_x,
            "coeffY": coeff_y,
            "predictions": predictions,
        }
        if scenario["name"] == "legacy-import":
            case["legacyPayload"] = {"corners": corners, "display": DISPLAY}
        cases.append(case)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps({"tolerance": 1e-6, "scenarios": cases}, indent=2) + "\n")
    print(f"generated {len(cases)} scenarios with 6 predictions each -> {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
