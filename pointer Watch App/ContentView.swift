//
//  ContentView.swift
//  pointer Watch App
//

import SwiftUI

struct ContentView: View {
    @StateObject private var motionManager = MotionManager()
    @State private var clickFlash = false
    @State private var calibStep: Int = 0 // 0 = off; 1...4 corners
    @State private var lastCalibLabel = ""

    private let calibCorners = ["tl", "tr", "bl", "br"]
    private let calibTitles = [
        "Top-left",
        "Top-right",
        "Bottom-left",
        "Bottom-right",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                header
                clickButton

                if motionManager.isTracking {
                    sensorGroup(title: "Attitude (rad)", rows: [
                        ("roll", motionManager.lastRoll),
                        ("yaw", motionManager.lastYaw),
                        ("pitch", motionManager.lastPitch),
                    ])

                    if calibStep > 0 {
                        calibPanel
                    } else {
                        Text("Cursor uses 4-corner calib on Mac. Start Calibrate, aim at each edge.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Button("Calibrate corners") {
                            startCalibration()
                        }
                        .tint(.purple)
                    }
                } else {
                    Text("Start tracking, then Calibrate TL→TR→BL→BR by pointing at each corner.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let err = motionManager.lastError {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
                if !lastCalibLabel.isEmpty {
                    Text(lastCalibLabel)
                        .font(.caption2)
                        .foregroundStyle(.green)
                }

                Button(action: { motionManager.toggleTracking() }) {
                    Text(motionManager.isTracking ? "Stop tracking" : "Start tracking")
                        .frame(maxWidth: .infinity)
                }
                .tint(motionManager.isTracking ? .red : .green)
            }
            .padding(.horizontal, 6)
        }
    }

    private var calibPanel: some View {
        let idx = max(0, min(calibCorners.count - 1, calibStep - 1))
        return VStack(alignment: .leading, spacing: 6) {
            Text("Calib \(calibStep)/4")
                .font(.caption.bold())
            Text("Cursor paused — aim at \(calibTitles[idx]) corner, then Capture.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button("Capture \(calibTitles[idx])") {
                captureCorner(idx)
            }
            .tint(.orange)
            Button("Cancel calib") {
                finishCalibration("Calibration cancelled")
            }
            .font(.caption2)
            Button("Clear Mac calib") {
                motionManager.sendCalibClear()
                finishCalibration("Clear sent")
            }
            .font(.caption2)
            .foregroundStyle(.red)
        }
    }

    /// Enter calibration: pause cursor tracking so the Mac cursor holds still while aiming.
    private func startCalibration() {
        motionManager.beginCalibration()
        calibStep = 1
        lastCalibLabel = ""
    }

    /// Leave calibration by any path: resume cursor tracking.
    private func finishCalibration(_ label: String) {
        motionManager.endCalibration()
        calibStep = 0
        lastCalibLabel = label
    }

    private func captureCorner(_ idx: Int) {
        let corner = calibCorners[idx]
        motionManager.sendCalibCorner(corner)
        lastCalibLabel = "Sent \(calibTitles[idx])"
        if calibStep >= 4 {
            finishCalibration("All 4 corners sent — tracking resumed")
        } else {
            calibStep += 1
        }
    }

    private var clickButton: some View {
        Button(action: fireClick) {
            HStack {
                Image(systemName: clickFlash ? "checkmark.circle.fill" : "hand.point.up.left.fill")
                Text(clickFlash ? "Clicked" : "Click / Double Tap")
                    .font(.caption.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(clickFlash ? .yellow : .blue)
        .handGestureShortcut(.primaryAction)
        .accessibilityLabel("Left click")
    }

    private func fireClick() {
        motionManager.sendClick()
        clickFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            clickFlash = false
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: motionManager.isTracking ? "waveform.path.ecg" : "sensor")
                    .foregroundStyle(motionManager.isTracking ? .green : .secondary)
                Text("Pointer")
                    .font(.headline)
            }
            HStack(spacing: 6) {
                if motionManager.isCalibrating {
                    pill("CALIB", .orange)
                } else {
                    pill(motionManager.isTracking ? "LIVE" : "IDLE", motionManager.isTracking ? .green : .gray)
                }
                if motionManager.isSimulatedSource {
                    pill("SIM", .purple)
                }
                pill(motionManager.sessionReachable ? "iPhone" : "no phone", motionManager.sessionReachable ? .blue : .orange)
                if motionManager.isTracking {
                    Text(String(format: "%.0f Hz", motionManager.samplesPerSecond))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func pill(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.25))
            .clipShape(Capsule())
    }

    private func sensorGroup(title: String, rows: [(String, Double)]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            ForEach(rows, id: \.0) { name, value in
                Text(String(format: "%@ %+8.4f", name, value))
                    .font(.system(.caption2, design: .monospaced))
            }
        }
    }
}

#Preview {
    ContentView()
}
