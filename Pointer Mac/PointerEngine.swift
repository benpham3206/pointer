import CoreGraphics
import Foundation

struct SourceArbitrator {
    static let phoneClaimLifetime: TimeInterval = 10

    private(set) var activeSource: PointerSource = .watch
    private(set) var phoneClaimExpiry: TimeInterval?

    mutating func handleClaim(source: PointerSource, active: Bool, now: TimeInterval) {
        guard source == .phone else { return }
        if active {
            phoneClaimExpiry = now + Self.phoneClaimLifetime
            activeSource = .phone
        } else {
            phoneClaimExpiry = nil
            activeSource = .watch
        }
    }

    @discardableResult
    mutating func refresh(now: TimeInterval) -> PointerSource {
        if activeSource == .phone, let phoneClaimExpiry, now >= phoneClaimExpiry {
            self.phoneClaimExpiry = nil
            activeSource = .watch
        }
        return activeSource
    }

    mutating func acceptsMotionOrCalibration(transport: String, now: TimeInterval) -> Bool {
        refresh(now: now)
        return !(activeSource == .phone && transport == "BLE")
    }
}

final class PointerEngine {
    private static let oneEuroMinCutoff = 1.0
    private static let oneEuroBeta = 0.4
    private static let oneEuroDerivativeCutoff = 1.0
    private static let springUpdateRate = 120.0
    private static let springTimeConstant = 0.080
    private static let trackingFreshnessLimit = 1.0
    private static let springPositionEpsilon = 0.01
    private static let springVelocityEpsilon = 0.1

    private weak var appState: AppState?
    private let synthesizer = CursorSynthesizer()
    private let calibrationURL: URL
    private let legacyCalibrationURL: URL

    private var display: PointerDisplay
    private var calibrationMap: CalibrationMap
    private var sourceArbitrator = SourceArbitrator()
    private(set) var activeSource: PointerSource = .watch
    private var rollFilter: OneEuroFilter
    private var yawFilter: OneEuroFilter
    private var pitchFilter: OneEuroFilter
    private var origins: [PointerSource: (roll: Double, yaw: Double, pitch: Double)] = [:]
    private var targetPoint: CGPoint?
    private var springPoint: CGPoint?
    private var springVelocity = CGPoint.zero
    private var lastMotionTimestamp: TimeInterval?
    private var lastSpringTimestamp: TimeInterval?
    private var springTimer: DispatchSourceTimer?
    private var claimExpiryTimer: DispatchSourceTimer?

    init(appState: AppState) {
        self.appState = appState
        display = PointerDisplay.pick(mode: appState.displayMode)
        calibrationMap = Self.makeMap(for: display)
        rollFilter = Self.makeOneEuroFilter()
        yawFilter = Self.makeOneEuroFilter()
        pitchFilter = Self.makeOneEuroFilter()

        let fileManager = FileManager.default
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        calibrationURL = applicationSupport
            .appendingPathComponent("Pointer", isDirectory: true)
            .appendingPathComponent("calibration.json")
        legacyCalibrationURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes", isDirectory: true)
            .appendingPathComponent("pointer-calib.json")

        loadCalibration()
        publishCalibrationState()
    }

    deinit {
        springTimer?.cancel()
        claimExpiryTimer?.cancel()
    }

    func handle(_ frame: PointerFrame, source: String) {
        let now = ProcessInfo.processInfo.systemUptime
        refreshActiveSource(now: now)
        switch frame {
        case let .motion(roll, yaw, pitch):
            guard sourceArbitrator.acceptsMotionOrCalibration(transport: source, now: now) else { return }
            appState?.recordFrame(source: source)
            updateTarget(roll: roll, yaw: yaw, pitch: pitch)
        case .click:
            report(synthesizer.leftClick())
        case .rightClick:
            report(synthesizer.rightClick())
        case let .calibration(corner, roll, yaw, pitch):
            guard sourceArbitrator.acceptsMotionOrCalibration(transport: source, now: now) else { return }
            setCorner(corner, roll: roll, yaw: yaw, pitch: pitch)
        case .calibrationClear:
            clearCalibration()
        case .reset:
            resetTracking()
        case let .sourceClaim(claimedSource, active):
            sourceArbitrator.handleClaim(source: claimedSource, active: active, now: now)
            refreshActiveSource(now: now)
            scheduleClaimExpiry(now: now)
        }
    }

    func selectDisplay(mode: String) {
        let selected = PointerDisplay.pick(mode: mode)
        let oldMap = calibrationMap
        display = selected
        calibrationMap = Self.makeMap(for: selected)
        for source in PointerSource.allCases {
            for corner in CalibrationMap.cornerOrder {
                guard let pose = oldMap.corners(for: source)[corner], pose.count >= 3 else { continue }
                calibrationMap.setCorner(
                    corner,
                    roll: pose[0],
                    yaw: pose[1],
                    pitch: pose[2],
                    source: source
                )
            }
        }
        resetTracking()
        publishCalibrationState()
    }

    func clearCalibration() {
        calibrationMap.clear(source: activeSource)
        resetTracking()
        do {
            if calibrationMap.hasAnyCorners {
                try saveCalibration()
            } else if FileManager.default.fileExists(atPath: calibrationURL.path) {
                try FileManager.default.removeItem(at: calibrationURL)
            }
        } catch {
            appState?.reportFailure(
                component: "PointerEngine.clearCalibration",
                rootCause: error.localizedDescription,
                failureType: "persistenceFailure"
            )
        }
        publishCalibrationState()
    }

    private func setCorner(_ corner: String, roll: Double, yaw: Double, pitch: Double) {
        guard calibrationMap.setCorner(
            corner,
            roll: roll,
            yaw: yaw,
            pitch: pitch,
            source: activeSource
        ),
              let uv = CalibrationMap.screenUV[corner]
        else {
            appState?.reportFailure(
                component: "PointerEngine.setCorner",
                rootCause: "Unknown calibration corner \(corner)",
                failureType: "invalidPayload"
            )
            return
        }

        let bounds = display.bounds
        let feedback = CGPoint(
            x: bounds.minX + uv.0 * (bounds.width - 1),
            y: bounds.minY + uv.1 * (bounds.height - 1)
        )
        report(synthesizer.postMouseMove(to: feedback))

        if calibrationMap.corners(for: activeSource).count == 4 {
            persistCalibration()
            if !calibrationMap.isCalibrated(for: activeSource) {
                appState?.reportFailure(
                    component: "PointerEngine.rebuildMap",
                    rootCause: "Corner roll or yaw spread is below 0.06 radians; staying in fallback tracking mode",
                    failureType: "invalidPayload"
                )
            }
        }
        publishCalibrationState()
    }

    private func updateTarget(roll: Double, yaw: Double, pitch: Double) {
        guard roll.isFinite, yaw.isFinite, pitch.isFinite else {
            appState?.reportFailure(
                component: "PointerEngine.updateTarget",
                rootCause: "Motion frame contains a non-finite attitude value",
                failureType: "invalidPayload"
            )
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        let roll = rollFilter.filter(roll, timestamp: now)
        let yaw = yawFilter.filter(yaw, timestamp: now)
        let pitch = pitchFilter.filter(pitch, timestamp: now)
        lastMotionTimestamp = now

        let bounds = display.bounds
        let target: CGPoint

        if let prediction = calibrationMap.predict(
            roll: roll,
            yaw: yaw,
            pitch: pitch,
            source: activeSource
        ),
           let appState {
            let midX = bounds.minX + bounds.width / 2
            let midY = bounds.minY + bounds.height / 2
            let nx = (prediction.x - midX) / (bounds.width / 2)
            let ny = (prediction.y - midY) / (bounds.height / 2)
            let gainX = appState.sensitivity * (1 + appState.accel * abs(nx))
            let gainY = appState.sensitivity * (1 + appState.accel * abs(ny))
            target = CGPoint(
                x: midX + (prediction.x - midX) * gainX,
                y: midY + (prediction.y - midY) * gainY
            )
        } else {
            guard let appState else { return }
            guard let origin = origins[activeSource] else {
                origins[activeSource] = (roll, yaw, pitch)
                return
            }
            let scaleX = bounds.width / 0.5
            let scaleY = bounds.height / 0.5
            target = CGPoint(
                x: bounds.minX + bounds.width / 2 + (yaw - origin.yaw) * scaleX * appState.sensitivity,
                y: bounds.minY + bounds.height / 2
                    - (roll - origin.roll) * scaleY * appState.sensitivity
                    - (pitch - origin.pitch) * scaleY * 0.3 * appState.sensitivity
            )
        }

        let clamped = CGPoint(
            x: max(bounds.minX, min(bounds.maxX - 1, target.x)),
            y: max(bounds.minY, min(bounds.maxY - 1, target.y))
        )
        let shouldUpdateTarget: Bool
        if let targetPoint, let appState {
            shouldUpdateTarget = hypot(clamped.x - targetPoint.x, clamped.y - targetPoint.y) >= appState.deadzone
        } else {
            shouldUpdateTarget = true
        }
        if shouldUpdateTarget {
            targetPoint = clamped
        }
        startSpringTimerIfNeeded()
    }

    private func startSpringTimerIfNeeded() {
        guard springTimer == nil, targetPoint != nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        let interval = DispatchTimeInterval.nanoseconds(Int((1_000_000_000 / Self.springUpdateRate).rounded()))
        timer.schedule(deadline: .now(), repeating: interval, leeway: .microseconds(500))
        timer.setEventHandler { [weak self] in
            self?.advanceSpring(now: ProcessInfo.processInfo.systemUptime)
        }
        springTimer = timer
        timer.resume()
    }

    private func advanceSpring(now: TimeInterval) {
        guard let lastMotionTimestamp,
              now - lastMotionTimestamp < Self.trackingFreshnessLimit
        else {
            stopSpringTimer()
            return
        }
        guard let targetPoint else {
            stopSpringTimer()
            return
        }

        guard let springPoint else {
            self.springPoint = targetPoint
            springVelocity = .zero
            lastSpringTimestamp = now
            report(synthesizer.postMouseMove(to: targetPoint))
            return
        }

        let elapsed = lastSpringTimestamp.map { now - $0 } ?? (1 / Self.springUpdateRate)
        lastSpringTimestamp = now
        guard elapsed > 0 else { return }

        let x = Self.advanceSpringAxis(
            position: springPoint.x,
            velocity: springVelocity.x,
            target: targetPoint.x,
            elapsed: elapsed
        )
        let y = Self.advanceSpringAxis(
            position: springPoint.y,
            velocity: springVelocity.y,
            target: targetPoint.y,
            elapsed: elapsed
        )
        var nextPoint = CGPoint(x: x.position, y: y.position)
        var nextVelocity = CGPoint(x: x.velocity, y: y.velocity)

        if hypot(nextPoint.x - targetPoint.x, nextPoint.y - targetPoint.y) < Self.springPositionEpsilon,
           hypot(nextVelocity.x, nextVelocity.y) < Self.springVelocityEpsilon {
            nextPoint = targetPoint
            nextVelocity = .zero
        }

        self.springPoint = nextPoint
        springVelocity = nextVelocity
        report(synthesizer.postMouseMove(to: nextPoint))
    }

    private func stopSpringTimer() {
        springTimer?.cancel()
        springTimer = nil
        lastSpringTimestamp = nil
    }

    private func resetTracking() {
        origins[activeSource] = nil
        resetMotionPipeline()
    }

    private func resetMotionPipeline() {
        stopSpringTimer()
        rollFilter.reset()
        yawFilter.reset()
        pitchFilter.reset()
        targetPoint = nil
        springPoint = nil
        springVelocity = .zero
        lastMotionTimestamp = nil
    }

    private func loadCalibration() {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: calibrationURL.path) {
            if !calibrationMap.load(from: calibrationURL) {
                appState?.reportFailure(
                    component: "PointerEngine.loadCalibration",
                    rootCause: "Could not decode \(calibrationURL.path)",
                    failureType: "invalidPayload"
                )
            }
            return
        }

        guard fileManager.fileExists(atPath: legacyCalibrationURL.path) else { return }
        guard calibrationMap.load(from: legacyCalibrationURL) else {
            appState?.reportFailure(
                component: "PointerEngine.importLegacyCalibration",
                rootCause: "Could not decode \(legacyCalibrationURL.path)",
                failureType: "invalidPayload"
            )
            return
        }
        persistCalibration()
    }

    private func persistCalibration() {
        do {
            try saveCalibration()
        } catch {
            appState?.reportFailure(
                component: "PointerEngine.persistCalibration",
                rootCause: error.localizedDescription,
                failureType: "persistenceFailure"
            )
        }
    }

    private func publishCalibrationState() {
        appState?.updateCalibration(
            isCalibrated: calibrationMap.isCalibrated(for: activeSource),
            corners: calibrationMap.calibratedCorners(for: activeSource)
        )
        appState?.updateSourceState(
            activeSource: activeSource.rawValue,
            watchCalibrated: calibrationMap.isCalibrated(for: .watch),
            phoneCalibrated: calibrationMap.isCalibrated(for: .phone)
        )
    }

    private func refreshActiveSource(now: TimeInterval) {
        let previous = activeSource
        activeSource = sourceArbitrator.refresh(now: now)
        guard activeSource != previous else { return }
        resetMotionPipeline()
        if activeSource == .watch {
            claimExpiryTimer?.cancel()
            claimExpiryTimer = nil
        }
        publishCalibrationState()
    }

    private func scheduleClaimExpiry(now: TimeInterval) {
        claimExpiryTimer?.cancel()
        claimExpiryTimer = nil
        guard activeSource == .phone, let expiry = sourceArbitrator.phoneClaimExpiry else { return }
        let delay = max(0, expiry - now)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + delay)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.refreshActiveSource(now: ProcessInfo.processInfo.systemUptime)
        }
        claimExpiryTimer = timer
        timer.resume()
    }

    private func saveCalibration() throws {
        try FileManager.default.createDirectory(
            at: calibrationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try calibrationMap.save(to: calibrationURL)
    }

    private func report(_ failure: CursorFailure?) {
        guard let failure else { return }
        appState?.reportFailure(
            component: failure.component,
            rootCause: failure.rootCause,
            failureType: failure.failureType
        )
    }

    private static func makeMap(for display: PointerDisplay) -> CalibrationMap {
        CalibrationMap(
            x0: Double(display.bounds.minX),
            y0: Double(display.bounds.minY),
            width: Double(display.bounds.width),
            height: Double(display.bounds.height),
            displayID: display.id,
            displayIsMain: display.isMain
        )
    }

    private static func makeOneEuroFilter() -> OneEuroFilter {
        OneEuroFilter(
            minCutoff: oneEuroMinCutoff,
            beta: oneEuroBeta,
            derivativeCutoff: oneEuroDerivativeCutoff
        )
    }

    private static func advanceSpringAxis(
        position: CGFloat,
        velocity: CGFloat,
        target: CGFloat,
        elapsed: TimeInterval
    ) -> (position: CGFloat, velocity: CGFloat) {
        let position = Double(position)
        let velocity = Double(velocity)
        let target = Double(target)
        let omega = 2 / springTimeConstant
        let offset = position - target
        let decay = exp(-omega * elapsed)
        let coefficient = (velocity + omega * offset) * elapsed
        let nextPosition = target + (offset + coefficient) * decay
        let nextVelocity = (velocity - omega * coefficient) * decay

        let direction = target - position
        let remaining = target - nextPosition
        if direction == 0 || direction * remaining <= 0 {
            return (CGFloat(target), 0)
        }
        return (CGFloat(nextPosition), CGFloat(nextVelocity))
    }
}
