//
//  MotionManager.swift
//  pointer Watch App
//

import Foundation
import CoreMotion
import WatchConnectivity
import Combine
import os

private struct WatchFailurePayload: CustomStringConvertible {
    let component: String
    let rootCause: String
    let failureType: String

    var description: String {
        "\(component) [\(failureType)]: \(rootCause)"
    }

    var dictionary: [String: String] {
        [
            "component": component,
            "rootCause": rootCause,
            "failureType": failureType,
        ]
    }
}

/// Live Watch IMU only (barometer disabled — was a crash candidate).
/// UI updates throttled; WCSession motion throttled; click is separate.
@MainActor
final class MotionManager: NSObject, ObservableObject {
    private let motion = CMMotionManager()
    private let trackingRuntime = TrackingRuntime()
    private let log = Logger(subsystem: "bp.pointer.watch", category: "IMU")
    private let motionQueue = OperationQueue()

    @Published var isTracking = false
    @Published var sessionReachable = false
    @Published var sessionActivated = false
    @Published var samplesPerSecond: Double = 0
    @Published var isSimulatedSource = false
    @Published var barometerAvailable = false
    @Published var lastError: String?

    @Published var lastRoll: Double = 0
    @Published var lastPitch: Double = 0
    @Published var lastYaw: Double = 0
    @Published var ax: Double = 0
    @Published var ay: Double = 0
    @Published var az: Double = 0
    @Published var gx: Double = 0
    @Published var gy: Double = 0
    @Published var gz: Double = 0
    @Published var relativeAltitudeM: Double?
    @Published var pressureKPa: Double?

    private var sampleCount = 0
    private var hzWindowStart = Date()
    private var simTimer: Timer?
    private var simPhase: Double = 0
    private var lastSend = Date.distantPast
    private var lastUIPublish = Date.distantPast
    private var lastWakeAttempt = Date.distantPast
    private let minSendInterval: TimeInterval = 0.05  // 20 Hz → phone (smoother cursor)
    private let minUIInterval: TimeInterval = 0.15    // ~6.5 Hz → SwiftUI
    private let minWakeInterval: TimeInterval = 1.0
    private var clickPiggyback = false

    // Latest raw sample (updated off main via hop)
    private var rawRoll = 0.0
    private var rawPitch = 0.0
    private var rawYaw = 0.0
    private var rawAx = 0.0
    private var rawAy = 0.0
    private var rawAz = 0.0
    private var rawGx = 0.0
    private var rawGy = 0.0
    private var rawGz = 0.0

    private var preferSimulated: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return !motion.isDeviceMotionAvailable
        #endif
    }

    override init() {
        super.init()
        motionQueue.name = "bp.pointer.watch.motion"
        motionQueue.maxConcurrentOperationCount = 1
        motionQueue.qualityOfService = .userInitiated

        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }

    func toggleTracking() {
        isTracking ? stopTracking() : startTracking()
    }

    func startTracking() {
        lastError = nil
        sampleCount = 0
        hzWindowStart = Date()
        simPhase = 0
        lastSend = .distantPast
        lastUIPublish = .distantPast
        lastWakeAttempt = .distantPast

        // Sensors work without phone.
        if preferSimulated {
            startSimulatedUpdates()
        } else {
            startHardwareUpdates()
        }
        isTracking = true
        trackingRuntime.onWillExpire = { [weak self] in
            // Keep IMU alive across session renewals.
            guard let self, self.isTracking else { return }
            self.trackingRuntime.start()
        }
        trackingRuntime.start()
        sendControl(["type": "reset"])
        log.notice("tracking started")
    }

    private func startHardwareUpdates() {
        isSimulatedSource = false
        guard motion.isDeviceMotionAvailable else {
            lastError = "Device motion unavailable — using SIM"
            startSimulatedUpdates()
            return
        }

        motion.stopDeviceMotionUpdates()
        // 20 Hz is plenty for cursor + display; safer on Watch than 60.
        motion.deviceMotionUpdateInterval = 1.0 / 20.0

        // Default reference frame (no .xArbitraryZVertical) — fewer crash paths.
        motion.startDeviceMotionUpdates(to: motionQueue) { [weak self] data, error in
            guard let self else { return }
            if let error {
                Task { @MainActor in
                    self.lastError = error.localizedDescription
                    self.log.error("motion: \(error.localizedDescription, privacy: .public)")
                }
                return
            }
            guard let data else { return }

            let roll = data.attitude.roll
            let pitch = data.attitude.pitch
            let yaw = data.attitude.yaw
            let ax = data.userAcceleration.x
            let ay = data.userAcceleration.y
            let az = data.userAcceleration.z
            let gx = data.rotationRate.x
            let gy = data.rotationRate.y
            let gz = data.rotationRate.z

            Task { @MainActor in
                self.handleSample(
                    roll: roll, pitch: pitch, yaw: yaw,
                    ax: ax, ay: ay, az: az,
                    gx: gx, gy: gy, gz: gz
                )
            }
        }
    }

    private func startSimulatedUpdates() {
        isSimulatedSource = true
        simTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isTracking else { return }
                self.simPhase += 0.12
                let t = self.simPhase
                self.handleSample(
                    roll: sin(t) * 0.4,
                    pitch: cos(t * 0.7) * 0.3,
                    yaw: t.truncatingRemainder(dividingBy: .pi * 2),
                    ax: sin(t * 2) * 0.05,
                    ay: cos(t * 2) * 0.05,
                    az: 0.98 + sin(t) * 0.02,
                    gx: sin(t) * 0.02,
                    gy: cos(t) * 0.02,
                    gz: sin(t * 0.5) * 0.01
                )
            }
        }
        simTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func handleSample(
        roll: Double, pitch: Double, yaw: Double,
        ax: Double, ay: Double, az: Double,
        gx: Double, gy: Double, gz: Double
    ) {
        rawRoll = roll
        rawPitch = pitch
        rawYaw = yaw
        rawAx = ax
        rawAy = ay
        rawAz = az
        rawGx = gx
        rawGy = gy
        rawGz = gz

        sampleCount += 1
        let elapsed = Date().timeIntervalSince(hzWindowStart)
        if elapsed >= 1.0 {
            samplesPerSecond = Double(sampleCount) / max(elapsed, 0.001)
            sampleCount = 0
            hzWindowStart = Date()
        }

        // Throttle SwiftUI @Published churn (crash / jetsam risk on watchOS).
        let now = Date()
        if now.timeIntervalSince(lastUIPublish) >= minUIInterval {
            lastUIPublish = now
            lastRoll = roll
            lastPitch = pitch
            lastYaw = yaw
            self.ax = ax
            self.ay = ay
            self.az = az
            self.gx = gx
            self.gy = gy
            self.gz = gz
        }

        sendMotionToPhoneIfNeeded(
            roll: roll, pitch: pitch, yaw: yaw,
            ax: ax, ay: ay, az: az,
            gx: gx, gy: gy, gz: gz
        )
    }

    private func sendMotionToPhoneIfNeeded(
        roll: Double, pitch: Double, yaw: Double,
        ax: Double, ay: Double, az: Double,
        gx: Double, gy: Double, gz: Double
    ) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        let now = Date()
        guard now.timeIntervalSince(lastSend) >= minSendInterval else { return }
        lastSend = now

        var dict: [String: Any] = [
            "roll": roll, "pitch": pitch, "yaw": yaw,
            "ax": ax, "ay": ay, "az": az,
            "gx": gx, "gy": gy, "gz": gz,
            "ts": now.timeIntervalSince1970,
        ]
        if clickPiggyback {
            dict["click"] = 1
            dict["type"] = "click"
            dict["button"] = "left"
            clickPiggyback = false
        }
        // applicationContext works even when isReachable == false (phone app still gets latest).
        do {
            try session.updateApplicationContext(dict)
        } catch {
            recordFailure(
                component: "MotionManager.sendMotionToPhoneIfNeeded",
                rootCause: error.localizedDescription,
                failureType: "transportUnavailable"
            )
        }
        if session.isReachable {
            session.sendMessage(dict, replyHandler: nil) { [weak self] error in
                Task { @MainActor in
                    self?.recordFailure(
                        component: "MotionManager.sendMotionToPhoneIfNeeded",
                        rootCause: error.localizedDescription,
                        failureType: "networkFailure"
                    )
                }
            }
        } else if now.timeIntervalSince(lastWakeAttempt) >= minWakeInterval {
            lastWakeAttempt = now
            var wake = dict
            wake["type"] = "wake"
            session.sendMessage(wake, replyHandler: nil) { [weak self] error in
                Task { @MainActor in
                    self?.recordFailure(
                        component: "MotionManager.wakePhone",
                        rootCause: error.localizedDescription,
                        failureType: "networkFailure"
                    )
                }
            }
        }
    }

    private func sendControl(_ dict: [String: Any]) {
        guard WCSession.isSupported() else {
            recordFailure(
                component: "MotionManager.sendControl",
                rootCause: "WatchConnectivity is not supported on this watch",
                failureType: "transportUnavailable"
            )
            return
        }
        let session = WCSession.default
        guard session.activationState == .activated else {
            recordFailure(
                component: "MotionManager.sendControl",
                rootCause: "WCSession is not activated",
                failureType: "activationFailure"
            )
            return
        }

        do {
            try session.updateApplicationContext(dict)
        } catch {
            recordFailure(
                component: "MotionManager.sendControl",
                rootCause: error.localizedDescription,
                failureType: "transportUnavailable"
            )
        }
        session.transferUserInfo(dict)
        session.sendMessage(dict, replyHandler: nil) { [weak self] error in
            Task { @MainActor in
                self?.recordFailure(
                    component: "MotionManager.sendControl",
                    rootCause: error.localizedDescription,
                    failureType: "networkFailure"
                )
            }
        }
    }

    /// Capture current attitude as a monitor corner for Mac calibration.
    func sendCalibCorner(_ corner: String) {
        let dict: [String: Any] = [
            "type": "calib",
            "corner": corner,
            "roll": lastRoll,
            "yaw": lastYaw,
            "pitch": lastPitch,
            "ts": Date().timeIntervalSince1970,
        ]
        sendControl(dict)
        log.notice("calib corner \(corner, privacy: .public)")
    }

    func sendCalibClear() {
        sendControl(["type": "calib_clear"])
    }

    /// Immediate left-click → iPhone → Mac (all delivery paths).
    func sendClick() {

        guard WCSession.isSupported() else {
            recordFailure(
                component: "MotionManager.sendClick",
                rootCause: "WatchConnectivity is not supported on this watch",
                failureType: "transportUnavailable"
            )
            return
        }
        let session = WCSession.default
        guard session.activationState == .activated else {
            recordFailure(
                component: "MotionManager.sendClick",
                rootCause: "WCSession is not activated",
                failureType: "activationFailure"
            )
            return
        }
        clickPiggyback = true
        let dict: [String: Any] = [
            "type": "click",
            "button": "left",
            "click": 1,
            "ts": Date().timeIntervalSince1970,
        ]
        lastError = nil
        sendControl(dict)
        log.notice("click delivery requested reachable=\(session.isReachable)")
    }

    func stopTracking() {
        trackingRuntime.stop()
        motion.stopDeviceMotionUpdates()
        simTimer?.invalidate()
        simTimer = nil
        isTracking = false
        samplesPerSecond = 0
        isSimulatedSource = false
        relativeAltitudeM = nil
        pressureKPa = nil
    }

    private func recordFailure(component: String, rootCause: String, failureType: String) {
        let failure = WatchFailurePayload(
            component: component,
            rootCause: rootCause,
            failureType: failureType
        )
        lastError = failure.description
        log.error("\(failure.description, privacy: .public)")
    }
}

extension MotionManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.sessionActivated = activationState == .activated
            self.sessionReachable = session.isReachable
            if let error {
                self.lastError = error.localizedDescription
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.sessionReachable = session.isReachable
        }
    }
}
