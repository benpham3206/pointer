//
//  PhoneCalibrationView.swift
//  pointer (iOS)
//
//  Corner-AGNOSTIC 4-corner calibration: aim at any corner in any order and
//  capture. Corners are classified from the captured poses themselves —
//  the left pair has the smaller azimuths, and within each pair the higher
//  elevation is the top corner. Labels never depend on capture order.
//

#if os(iOS)
import SwiftUI

struct PhoneCalibrationView: View {
    /// Current filtered attitude from the pointer engine (nil until streaming).
    var captureAttitude: () -> (roll: Double, yaw: Double, pitch: Double)?
    /// Send one labeled corner to the Mac: (cornerName, pose).
    var sendCorner: (String, (roll: Double, yaw: Double, pitch: Double)) -> Void
    var onFinished: (String) -> Void

    @State private var captured: [(roll: Double, yaw: Double, pitch: Double)] = []
    @State private var message: String?
    private let haptic = UINotificationFeedbackGenerator()

    /// Corners must span at least this many radians in both axes (matches the
    /// Mac's MIN_CALIB_SPAN degenerate guard) before we try to classify.
    private static let minSpan = 0.06

    var body: some View {
        VStack(spacing: 12) {
            Text("Aim the top of the phone at any screen corner, then Capture. Any order — the app works out which corner is which.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i < captured.count ? Color.green : Color.secondary.opacity(0.25))
                        .frame(width: 12, height: 12)
                }
            }

            Button {
                capture()
            } label: {
                Label("Capture corner \(captured.count + 1) of 4", systemImage: "scope")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(captured.count >= 4)

            if let message {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

            Button("Start over", role: .destructive) {
                captured.removeAll()
                message = nil
            }
            .font(.caption)
            .disabled(captured.isEmpty)
        }
        .padding(.vertical, 4)
    }

    private func capture() {
        guard let pose = captureAttitude() else {
            message = "No motion yet — turn the pointer toggle on first."
            haptic.notificationOccurred(.error)
            return
        }
        captured.append(pose)
        haptic.notificationOccurred(.success)
        message = nil
        guard captured.count == 4 else { return }

        if let labeled = Self.classify(captured) {
            for (name, pose) in labeled {
                sendCorner(name, pose)
            }
            onFinished("Calibrated — 4 corners mapped")
        } else {
            captured.removeAll()
            message = "Corners too close together or ambiguous — aim wider and re-capture all 4."
            haptic.notificationOccurred(.error)
        }
    }

    /// Classify 4 unlabeled poses into tl/tr/bl/br by relative geometry.
    /// Assumes the engine's convention: azimuth (yaw) increases toward screen-right.
    static func classify(
        _ poses: [(roll: Double, yaw: Double, pitch: Double)]
    ) -> [(String, (roll: Double, yaw: Double, pitch: Double))]? {
        guard poses.count == 4 else { return nil }

        let yaws = poses.map(\.yaw)
        let rolls = poses.map(\.roll)
        guard let yMin = yaws.min(), let yMax = yaws.max(),
              let rMin = rolls.min(), let rMax = rolls.max(),
              yMax - yMin >= minSpan, rMax - rMin >= minSpan else { return nil }

        // Left pair = two smallest azimuths; right pair = two largest.
        let byYaw = poses.sorted { $0.yaw < $1.yaw }
        let left = Array(byYaw.prefix(2)), right = Array(byYaw.suffix(2))

        // Guard: the pairs must be separated in azimuth (a real 2×2 grid).
        guard right[0].yaw - left[1].yaw >= minSpan / 2 else { return nil }

        func topBottom(_ pair: [(roll: Double, yaw: Double, pitch: Double)])
            -> (top: (roll: Double, yaw: Double, pitch: Double), bottom: (roll: Double, yaw: Double, pitch: Double))? {
            guard abs(pair[0].roll - pair[1].roll) >= minSpan / 2 else { return nil }
            return pair[0].roll > pair[1].roll ? (pair[0], pair[1]) : (pair[1], pair[0])
        }
        guard let l = topBottom(left), let r = topBottom(right) else { return nil }

        return [("tl", l.top), ("bl", l.bottom), ("tr", r.top), ("br", r.bottom)]
    }
}
#endif
