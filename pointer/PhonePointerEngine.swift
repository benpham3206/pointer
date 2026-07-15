//
//  PhonePointerEngine.swift
//  pointer
//

#if os(iOS)
import Combine
import CoreMotion
import Foundation

/// Streams the iPhone's +Y axis as a world-space pointing ray.
@MainActor
final class PhonePointerEngine: ObservableObject {
    typealias FrameSink = ([String: Any]) -> Void

    @Published private(set) var isActive = false
    /// True while capturing calibration corners: the filter keeps running (so
    /// currentFilteredAttitude stays live for capture) but cursor frames stop,
    /// holding the Mac cursor still while aiming — same semantics as the watch.
    @Published var isCalibrating = false
    @Published private(set) var lastFailure: [String: String]?

    private let motion = CMMotionManager()
    private let motionQueue: OperationQueue
    private let sink: FrameSink
    private let motionHz = 15.0
    private let attitudeEmaAlpha = 0.08
    private let attitudeEmaSpeedGain = 10.0

    private var lastFrameAt = Date.distantPast
    private var startedAt = Date.distantPast
    private let settleInterval: TimeInterval = 0.3
    private var previousWrappedYaw: Double?
    private var unwrappedYaw = 0.0
    private var emaInitialized = false
    private var emaRoll = 0.0
    private var emaPitch = 0.0
    private var emaYaw = 0.0

    init(sink: @escaping FrameSink) {
        self.sink = sink
        let queue = OperationQueue()
        queue.name = "bp.pointer.phone.motion"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
        self.motionQueue = queue
    }

    func start() {
        guard !isActive else { return }
        guard motion.isDeviceMotionAvailable else {
            recordFailure(
                rootCause: "Device motion is unavailable on this iPhone",
                failureType: "unavailableResource"
            )
            return
        }

        resetFilter()
        startedAt = Date()
        lastFailure = nil
        motion.deviceMotionUpdateInterval = 1.0 / motionHz
        motion.startDeviceMotionUpdates(
            using: .xArbitraryZVertical,
            to: motionQueue
        ) { [weak self] deviceMotion, error in
            if let error {
                Task { @MainActor [weak self] in
                    self?.recordFailure(
                        rootCause: error.localizedDescription,
                        failureType: "motionUpdateFailure"
                    )
                }
                return
            }
            guard let deviceMotion else { return }
            Task { @MainActor [weak self] in
                self?.handle(deviceMotion)
            }
        }
        isActive = true
    }

    func stop() {
        guard isActive else { return }
        motion.stopDeviceMotionUpdates()
        isActive = false
    }

    private func resetFilter() {
        lastFrameAt = .distantPast
        previousWrappedYaw = nil
        unwrappedYaw = 0
        emaInitialized = false
    }

    private func recordFailure(rootCause: String, failureType: String) {
        motion.stopDeviceMotionUpdates()
        isActive = false
        lastFailure = [
            "component": "PhonePointerEngine",
            "rootCause": rootCause,
            "failureType": failureType,
        ]
    }

    private func handle(_ deviceMotion: CMDeviceMotion) {
        guard isActive else { return }

        // Core Motion's attitude matrix maps device axes into the reference frame,
        // so its second column is device +Y (toward the top speaker) in world space.
        let matrix = deviceMotion.attitude.rotationMatrix
        // CMAttitude's rotationMatrix rows (not columns) are the device axes
        // expressed in the reference frame: device +Y in world = (m21, m22, m23).
        // Reading the column (m12,m22,m32) — the transpose — flipped BOTH screen
        // axes on hardware (left→right, up→down).
        let worldX = matrix.m21
        let worldY = matrix.m22
        let worldZ = matrix.m23
        // Azimuth must INCREASE pointing right: with the horizontal ray at angle α
        // CCW-from-+X, atan2(worldX, worldY) gives 0 at +Y, +π/2 at +X (right),
        // -π/2 at -X (left). The previous atan2(-worldX, worldY) was inverted.
        let wrappedYaw = atan2(worldX, worldY)
        let roll = atan2(worldZ, hypot(worldX, worldY))

        if let previousWrappedYaw {
            let delta = atan2(
                sin(wrappedYaw - previousWrappedYaw),
                cos(wrappedYaw - previousWrappedYaw)
            )
            unwrappedYaw += delta
        } else {
            unwrappedYaw = wrappedYaw
        }
        previousWrappedYaw = wrappedYaw

        let pitch = deviceMotion.attitude.pitch
        if emaInitialized {
            emaRoll = angularEma(emaRoll, roll)
            emaPitch = angularEma(emaPitch, pitch)
            emaYaw = angularEma(emaYaw, unwrappedYaw)
        } else {
            emaRoll = roll
            emaPitch = pitch
            emaYaw = unwrappedYaw
            emaInitialized = true
        }

        let now = Date()
        // Hold the cursor still while the user aims at calibration corners.
        guard !isCalibrating else { return }
        // Settle: let the EMA converge (~0.3 s) after start before emitting, so the
        // Mac's fallback origin isn't captured from a half-settled pose (right-bias fix).
        guard now.timeIntervalSince(startedAt) >= settleInterval else { return }
        guard now.timeIntervalSince(lastFrameAt) >= 1.0 / motionHz else { return }
        lastFrameAt = now
        sink([
            "roll": emaRoll,
            "yaw": emaYaw,
            // Emit 0 — attitude twist is meaningless for a ray pointer, and the Mac's
            // uncalibrated fallback couples pitch into Y, distorting elevation.
            "pitch": 0.0,
            "ts": now.timeIntervalSince1970,
        ])
    }

    /// Current EMA-filtered pointing attitude (nil until the filter has settled).
    /// Used by the corner-agnostic calibration UI to capture poses.
    func currentFilteredAttitude() -> (roll: Double, yaw: Double, pitch: Double)? {
        guard emaInitialized, Date().timeIntervalSince(startedAt) >= settleInterval else { return nil }
        return (emaRoll, emaYaw, 0.0)
    }

    /// Matches the Watch's adaptive angular EMA exactly.
    private func angularEma(_ current: Double, _ sample: Double) -> Double {
        let delta = atan2(sin(sample - current), cos(sample - current))
        let alpha = min(0.9, attitudeEmaAlpha + abs(delta) * attitudeEmaSpeedGain)
        return current + alpha * delta
    }
}
#endif
