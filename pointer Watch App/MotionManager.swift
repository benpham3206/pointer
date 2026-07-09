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
    /// True while the user is capturing calibration corners. Cursor streaming is paused
    /// (so the Mac cursor holds still while aiming) but IMU sampling keeps running.
    @Published var isCalibrating = false

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
    private var lastMotionErrorAt = Date.distantPast
    private let minSendInterval: TimeInterval = 0.05  // 20 Hz → phone (smoother cursor)
    private let minUIInterval: TimeInterval = 0.15    // ~6.5 Hz → SwiftUI

    // Error mirroring to the paired iPhone (throttled, guaranteed transport).
    private var lastMirrorMessage: String?
    private var lastMirrorAt = Date.distantPast

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

    // Exponential moving-average low-pass on attitude — smooths the cursor.
    // alpha 0.1–0.2 is the sweet spot between lag and smoothness; tweak here.
    private let attitudeEmaAlpha = 0.15
    private var emaInitialized = false
    private var emaRoll = 0.0
    private var emaPitch = 0.0
    private var emaYaw = 0.0

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
        emaInitialized = false

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
            setLastError("Device motion unavailable — using SIM")
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
                    self.setLastError("MotionManager.motion: \(error.localizedDescription)")
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

        // EMA low-pass the attitude (what drives the cursor). Angle-aware so values
        // near ±π don't glitch. First sample seeds the filter to avoid a ramp from 0.
        if emaInitialized {
            emaRoll = angularEma(emaRoll, roll)
            emaPitch = angularEma(emaPitch, pitch)
            emaYaw = angularEma(emaYaw, yaw)
        } else {
            emaRoll = roll
            emaPitch = pitch
            emaYaw = yaw
            emaInitialized = true
        }

        sampleCount += 1
        let elapsed = Date().timeIntervalSince(hzWindowStart)
        if elapsed >= 1.0 {
            samplesPerSecond = Double(sampleCount) / max(elapsed, 0.001)
            sampleCount = 0
            hzWindowStart = Date()
        }

        // Throttle SwiftUI @Published churn (crash / jetsam risk on watchOS).
        // Publish the FILTERED attitude so the display matches what the cursor uses.
        let now = Date()
        if now.timeIntervalSince(lastUIPublish) >= minUIInterval {
            lastUIPublish = now
            lastRoll = emaRoll
            lastPitch = emaPitch
            lastYaw = emaYaw
            self.ax = ax
            self.ay = ay
            self.az = az
            self.gx = gx
            self.gy = gy
            self.gz = gz
        }

        // Send the smoothed attitude to the Mac (accel/gyro pass through raw — display only).
        sendMotionToPhoneIfNeeded(
            roll: emaRoll, pitch: emaPitch, yaw: emaYaw,
            ax: ax, ay: ay, az: az,
            gx: gx, gy: gy, gz: gz
        )
    }

    /// EMA step that respects angle wrap-around (shortest path), so roll/yaw near ±π
    /// don't average across the seam into a wrong value.
    private func angularEma(_ current: Double, _ sample: Double) -> Double {
        let delta = atan2(sin(sample - current), cos(sample - current))
        return current + attitudeEmaAlpha * delta
    }

    private func sendMotionToPhoneIfNeeded(
        roll: Double, pitch: Double, yaw: Double,
        ax: Double, ay: Double, az: Double,
        gx: Double, gy: Double, gz: Double
    ) {
        // Hold the cursor still while the user aims at calibration corners.
        guard !isCalibrating else { return }
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        let now = Date()
        guard now.timeIntervalSince(lastSend) >= minSendInterval else { return }
        lastSend = now

        let dict: [String: Any] = [
            "roll": roll, "pitch": pitch, "yaw": yaw,
            "ax": ax, "ay": ay, "az": az,
            "gx": gx, "gy": gy, "gz": gz,
            "ts": now.timeIntervalSince1970,
        ]
        // applicationContext keeps the phone's latest sample even when unreachable
        // (coalesced, best-effort). Discrete clicks go separately via sendControl.
        do {
            try session.updateApplicationContext(dict)
        } catch {
            // Transient — log only, don't nag the UI (see recordMotionSendFailure).
            log.error("applicationContext (transient): \(error.localizedDescription, privacy: .public)")
        }
        // Realtime path only when the phone is actually reachable. No "wake" pings:
        // sendMessage requires reachability, so pinging while unreachable only ever
        // produced the networkFailure errors the user was seeing.
        guard session.isReachable else { return }
        session.sendMessage(dict, replyHandler: nil) { [weak self] error in
            Task { @MainActor in
                self?.recordMotionSendFailure(error.localizedDescription)
            }
        }
    }

    /// Realtime motion-send hiccups are transient (phone briefly unreachable) and
    /// self-heal on the next reachable frame — log them for debugging but never surface
    /// them as a user-facing error or mirror them to the phone.
    private func recordMotionSendFailure(_ rootCause: String) {
        let now = Date()
        guard now.timeIntervalSince(lastMotionErrorAt) >= 1.0 else { return }
        lastMotionErrorAt = now
        log.error("motion send (transient): \(rootCause, privacy: .public)")
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

        // Discrete control events (reset / calib / click) must arrive exactly once.
        //  • Reachable   → low-latency sendMessage; on a real error, fall back to the
        //                  guaranteed queue instead of surfacing a networkFailure.
        //  • Unreachable → transferUserInfo (guaranteed, FIFO, survives app relaunch).
        // Sending via a single transport (not all three) avoids duplicate delivery —
        // which previously produced double-clicks — and removes the spurious
        // "sendControl [networkFailure]" seen whenever the phone was not foregrounded.
        if session.isReachable {
            session.sendMessage(dict, replyHandler: nil) { [weak self] error in
                Task { @MainActor in
                    guard let self else { return }
                    WCSession.default.transferUserInfo(dict)
                    self.log.error("sendControl live send failed, queued via transferUserInfo: \(error.localizedDescription, privacy: .public)")
                }
            }
        } else {
            session.transferUserInfo(dict)
        }
    }

    /// Enter calibration: pause cursor streaming (IMU keeps running so corners settle).
    func beginCalibration() {
        isCalibrating = true
        log.notice("calibration started — cursor streaming paused")
    }

    /// Leave calibration: resume streaming the (now calibrated) motion to the Mac.
    func endCalibration() {
        guard isCalibrating else { return }
        isCalibrating = false
        lastSend = .distantPast
        log.notice("calibration ended — cursor streaming resumed")
    }

    /// Capture current attitude as a monitor corner for Mac calibration.
    func sendCalibCorner(_ corner: String) {
        // Capture the smoothed (EMA) attitude so the corner pose matches the live
        // filtered motion the Mac fits its map against.
        let dict: [String: Any] = [
            "type": "calib",
            "corner": corner,
            "roll": emaRoll,
            "yaw": emaYaw,
            "pitch": emaPitch,
            "ts": Date().timeIntervalSince1970,
        ]
        sendControl(dict)
        log.notice("calib corner \(corner, privacy: .public) roll=\(self.emaRoll) yaw=\(self.emaYaw)")
    }

    func sendCalibClear() {
        sendControl(["type": "calib_clear"])
    }

    /// Immediate left-click → iPhone → Mac (all delivery paths).
    func sendClick() {
        let dict: [String: Any] = [
            "type": "click",
            "button": "left",
            "click": 1,
            "ts": Date().timeIntervalSince1970,
        ]
        lastError = nil
        // sendControl delivers exactly once (sendMessage when reachable, else the
        // guaranteed transferUserInfo queue) — no more double-clicks or lost taps.
        sendControl(dict)
        log.notice("click delivery requested reachable=\(WCSession.default.isReachable)")
    }

    func stopTracking() {
        trackingRuntime.stop()
        motion.stopDeviceMotionUpdates()
        simTimer?.invalidate()
        simTimer = nil
        isTracking = false
        isCalibrating = false
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
        setLastError(failure.description)
        log.error("\(failure.description, privacy: .public)")
    }

    /// Sets the watch-visible error and mirrors it to the paired iPhone.
    private func setLastError(_ message: String) {
        lastError = message
        mirrorErrorToPhone(message)
    }

    /// Mirror a watch error to the iPhone companion (throttled, guaranteed transport).
    private func mirrorErrorToPhone(_ message: String) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let now = Date()
        // Avoid flooding: skip identical messages within a short window.
        if message == lastMirrorMessage, now.timeIntervalSince(lastMirrorAt) < 2.0 { return }
        lastMirrorMessage = message
        lastMirrorAt = now
        let payload: [String: Any] = [
            "type": "watch_error",
            "message": message,
            "ts": now.timeIntervalSince1970,
        ]
        // Deliver immediately when the phone is reachable (foreground) so the error
        // shows up right away — transferUserInfo is a background transfer that is
        // delayed on-device and does not deliver between simulators. Fall back to the
        // guaranteed queue when unreachable. Never record a failure here (would recurse).
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                WCSession.default.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
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
                self.setLastError("MotionManager.session activation: \(error.localizedDescription)")
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.sessionReachable = session.isReachable
        }
    }
}
