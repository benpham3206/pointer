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
    private let bleTransport = BLETransport()
    private let log = Logger(subsystem: "bp.pointer.watch", category: "IMU")
    private let motionQueue = OperationQueue()

    @Published var isTracking = false
    @Published var sessionReachable = false
    @Published var sessionActivated = false
    @Published private(set) var bleLinkState: BLETransport.LinkState = .starting
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
    // Lower rate = less Watch CoreMotion + WCSession traffic = better battery.
    private let motionHz: Double = 15
    private var minSendInterval: TimeInterval { 1.0 / motionHz }
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

    // Adaptive EMA (One-Euro-lite): base = heavy smoothing when nearly still (kills
    // jitter); alpha ramps up with angular speed for low lag when actually moving.
    private let attitudeEmaAlpha = 0.08
    private let attitudeEmaSpeedGain = 10.0
    private var previousWrappedYaw: Double?
    private var unwrappedYaw = 0.0
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

        bleLinkState = bleTransport.linkState
        bleTransport.onLinkStateChanged = { [weak self] state in
            self?.bleLinkState = state
        }
        bleTransport.onFailure = { [weak self] failure in
            self?.recordFailure(
                component: failure.component,
                rootCause: failure.rootCause,
                failureType: failure.failureType
            )
        }

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
        previousWrappedYaw = nil
        unwrappedYaw = 0
        emaInitialized = false

        // Sensors work without phone.
        if preferSimulated {
            startSimulatedUpdates()
        } else {
            startHardwareUpdates()
        }
        isTracking = true
        WorkoutKeepAlive.shared.onFailure = { [weak self] rootCause, failureType in
            self?.recordFailure(
                component: "WorkoutKeepAlive",
                rootCause: rootCause,
                failureType: failureType
            )
        }
        WorkoutKeepAlive.shared.fallback = { [weak self] in
            guard let self, self.isTracking else { return }
            self.trackingRuntime.onWillExpire = { [weak self] in
                // Keep IMU alive across session renewals.
                guard let self, self.isTracking else { return }
                self.trackingRuntime.start()
            }
            self.trackingRuntime.start()
        }
        WorkoutKeepAlive.shared.start()
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
        motion.deviceMotionUpdateInterval = 1.0 / motionHz

        // Explicit Z-vertical frame is required for world-space ray angles. Stop updates
        // first above and retain the availability guard to keep the safe restart pattern.
        motion.startDeviceMotionUpdates(
            using: .xArbitraryZVertical,
            to: motionQueue
        ) { [weak self] data, error in
            guard let self else { return }
            if let error {
                Task { @MainActor in
                    self.setLastError("MotionManager.motion: \(error.localizedDescription)")
                    self.log.error("motion: \(error.localizedDescription, privacy: .public)")
                }
                return
            }
            guard let data else { return }

            // CMAttitude rotation-matrix rows are device axes expressed in the
            // reference frame. The band follows device ±Y, so row 2 is its world ray.
            let matrix = data.attitude.rotationMatrix
            let worldX = matrix.m21
            let worldY = matrix.m22
            let worldZ = matrix.m23
            let roll = atan2(worldZ, hypot(worldX, worldY))
            let pitch = data.attitude.pitch
            let yaw = atan2(worldX, worldY)
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
        let timer = Timer(timeInterval: 1.0 / motionHz, repeats: true) { [weak self] _ in
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

        // Accumulate azimuth along the shortest path across the ±π seam so the
        // filtered pointing ray remains continuous through a full turn.
        if let previousWrappedYaw {
            let delta = atan2(
                sin(yaw - previousWrappedYaw),
                cos(yaw - previousWrappedYaw)
            )
            unwrappedYaw += delta
        } else {
            unwrappedYaw = yaw
        }
        previousWrappedYaw = yaw

        // EMA low-pass the pointing ray (what drives the cursor). Angle-aware so values
        // near ±π don't glitch. First sample seeds the filter to avoid a ramp from 0.
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

        // Send the smoothed ray to the Mac (accel/gyro pass through raw — display only).
        sendMotion(
            roll: emaRoll, pitch: 0, yaw: emaYaw,
            ax: ax, ay: ay, az: az,
            gx: gx, gy: gy, gz: gz
        )
    }

    /// EMA step that respects angle wrap-around (shortest path), so ray angles near ±π
    /// don't average across the seam into a wrong value.
    private func angularEma(_ current: Double, _ sample: Double) -> Double {
        let delta = atan2(sin(sample - current), cos(sample - current))
        // |delta| is per-sample angular speed: still → base alpha, fast → up to 0.9.
        let alpha = min(0.9, attitudeEmaAlpha + abs(delta) * attitudeEmaSpeedGain)
        return current + alpha * delta
    }

    private func sendMotion(
        roll: Double, pitch: Double, yaw: Double,
        ax: Double, ay: Double, az: Double,
        gx: Double, gy: Double, gz: Double
    ) {
        // Hold the cursor still while the user aims at calibration corners.
        guard !isCalibrating else { return }

        let now = Date()
        guard now.timeIntervalSince(lastSend) >= minSendInterval else { return }
        lastSend = now

        // A connected Mac peripheral is the direct low-latency path. Motion may be
        // dropped under BLE backpressure; the next 15 Hz sample replaces it.
        if bleTransport.sendMotion(roll: roll, yaw: yaw, pitch: pitch) {
            return
        }

        sendMotionToPhone(
            roll: roll, pitch: pitch, yaw: yaw,
            ax: ax, ay: ay, az: az,
            gx: gx, gy: gy, gz: gz,
            now: now
        )
    }

    private func sendMotionToPhone(
        roll: Double, pitch: Double, yaw: Double,
        ax: Double, ay: Double, az: Double,
        gx: Double, gy: Double, gz: Double,
        now: Date
    ) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

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
        if let frame = BLETransport.frame(for: dict), bleTransport.sendControl(frame) {
            return
        }
        sendControlToPhone(dict)
    }

    private func sendControlToPhone(_ dict: [String: Any]) {
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

    /// Capture the current pointing ray as a monitor corner for Mac calibration.
    func sendCalibCorner(_ corner: String) {
        // Capture the smoothed (EMA) ray so the corner pose matches the live
        // filtered motion the Mac fits its map against.
        let dict: [String: Any] = [
            "type": "calib",
            "corner": corner,
            "roll": emaRoll,
            "yaw": emaYaw,
            "pitch": 0.0,
            "ts": Date().timeIntervalSince1970,
        ]
        sendControl(dict)
        log.notice("calib corner \(corner, privacy: .public) roll=\(self.emaRoll) yaw=\(self.emaYaw)")
    }

    func sendCalibClear() {
        sendControl(["type": "calib_clear"])
    }

    /// Type literal text on the Mac (BLE control channel, phone-relay fallback).
    func sendText(_ text: String) {
        guard !text.isEmpty else { return }
        sendControl(["type": "text", "text": text])
    }

    /// Tap a special key on the Mac (kVK keycode; modifiers bit0 shift…bit3 cmd).
    func sendKey(keycode: Int, modifiers: Int = 0) {
        sendControl(["type": "key", "keycode": keycode, "modifiers": modifiers, "action": 2])
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
        WorkoutKeepAlive.shared.stop()
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
