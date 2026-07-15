import Combine
import SwiftUI

final class AppState: ObservableObject {
    @AppStorage("sensitivity") private var storedSensitivity = 0.45
    @AppStorage("deadzone") private var storedDeadzone = 2.0
    @AppStorage("accel") private var storedAccel = 1.5
    @AppStorage("displayMode") private var storedDisplayMode = "external"

    @Published var sensitivity: Double = 0.45 {
        didSet { storedSensitivity = sensitivity }
    }
    @Published var deadzone: Double = 2.0 {
        didSet { storedDeadzone = deadzone }
    }
    @Published var accel: Double = 1.5 {
        didSet { storedAccel = accel }
    }
    @Published var displayMode: String = "external" {
        didSet {
            storedDisplayMode = displayMode
            engine?.selectDisplay(mode: displayMode)
        }
    }

    @Published private(set) var udpState = "starting"
    @Published private(set) var bleState = "off — starting"
    @Published private(set) var framesPerSecond = 0.0
    @Published private(set) var lastSource = "none"
    @Published private(set) var isCalibrated = false
    @Published private(set) var calibratedCorners: [String] = []
    @Published private(set) var lastFailure: String?
    @Published private(set) var activeSource = PointerSource.watch.rawValue
    @Published private(set) var watchCalibrated = false
    @Published private(set) var phoneCalibrated = false

    private var engine: PointerEngine?
    private var udpListener: UDPListener?
    private var bleService: BLEPeripheralService?
    private var frameTimes: [TimeInterval] = []
    private var statsTimer: Timer?

    init() {
        sensitivity = storedSensitivity
        deadzone = storedDeadzone
        accel = storedAccel
        displayMode = storedDisplayMode

        let engine = PointerEngine(appState: self)
        self.engine = engine

        let udpListener = UDPListener(
            onFrame: { [weak engine] frame in engine?.handle(frame, source: "UDP") },
            appState: self
        )
        self.udpListener = udpListener

        let bleService = BLEPeripheralService(
            onFrame: { [weak engine] frame in engine?.handle(frame, source: "BLE") },
            appState: self
        )
        self.bleService = bleService

        statsTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refreshFrameRate()
        }
        udpListener.start()
        bleService.start()
    }

    deinit {
        statsTimer?.invalidate()
        udpListener?.stop()
        bleService?.stop()
    }

    func clearCalibration() {
        engine?.clearCalibration()
    }

    func setUDPState(_ state: String) {
        udpState = state
    }

    func setBLEState(_ state: String) {
        bleState = state
    }

    func updateCalibration(isCalibrated: Bool, corners: [String]) {
        self.isCalibrated = isCalibrated
        calibratedCorners = corners
    }

    func updateSourceState(activeSource: String, watchCalibrated: Bool, phoneCalibrated: Bool) {
        self.activeSource = activeSource
        self.watchCalibrated = watchCalibrated
        self.phoneCalibrated = phoneCalibrated
    }

    func recordFrame(source: String) {
        let now = ProcessInfo.processInfo.systemUptime
        frameTimes.append(now)
        lastSource = source
        refreshFrameRate(now: now)
    }

    func reportFailure(component: String, rootCause: String, failureType: String) {
        lastFailure = "{component: \(component), rootCause: \(rootCause), failureType: \(failureType)}"
    }

    func clearFailure(component: String) {
        guard lastFailure?.contains("component: \(component)") == true else { return }
        lastFailure = nil
    }

    private func refreshFrameRate(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        frameTimes.removeAll { now - $0 > 1.0 }
        framesPerSecond = Double(frameTimes.count)
    }
}
