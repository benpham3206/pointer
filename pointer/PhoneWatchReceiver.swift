//
//  PhoneWatchReceiver.swift
//  pointer
//

#if os(iOS)
import Combine
import Foundation
import UIKit
import WatchConnectivity

/// iOS WCSession receiver: Watch messages for UI + Mac relay + optional Python debug TCP.
final class PhoneWatchReceiver: NSObject, ObservableObject, WCSessionDelegate {
    let relayState: PhoneRelayState
    let macForwarder: MacForwarder
    let sensorDebugStreamer = SensorDebugStreamer()

    private let session: WCSession
    private var pollTimer: Timer?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var didRequestActivation = false
    private var cancellables: Set<AnyCancellable> = []

    init(relayState: PhoneRelayState = PhoneRelayState(), macForwarder: MacForwarder = MacForwarder()) {
        self.relayState = relayState
        self.macForwarder = macForwarder
        self.session = WCSession.default
        super.init()
        bindNestedState()
        installLifecycleObservers()
        activateSessionIfNeeded()
    }

    deinit {
        pollTimer?.invalidate()
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        endRelayBackgroundTask()
    }

    func activateSessionIfNeeded() {
        guard WCSession.isSupported() else {
            relayState.applyFailure(
                component: "PhoneWatchReceiver.activateSessionIfNeeded",
                rootCause: "WatchConnectivity is not supported on this device",
                failureType: .transportUnavailable
            )
            return
        }
        session.delegate = self
        if session.activationState != .activated, !didRequestActivation {
            didRequestActivation = true
            session.activate()
        }
        refreshFlags()
        macForwarder.ensureConnected()
        startPollingFlags()
    }

    private func startPollingFlags() {
        pollTimer?.invalidate()
        // Reachability / install flags can lag; poll while app is up.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshFlags()
            self?.macForwarder.ensureConnected()
        }
    }

    private func refreshFlags() {
        DispatchQueue.main.async {
            self.relayState.applyReachability(self.session.isReachable)
            self.relayState.applySessionFlags(
                paired: self.session.isPaired,
                appInstalled: self.session.isWatchAppInstalled
            )
            if self.session.activationState == .activated {
                self.relayState.applyActivation(.activated, error: nil)
            }
        }
    }

    func updateDebugStream(host: String, port: UInt16, enabled: Bool) {
        sensorDebugStreamer.configure(host: host, port: port, enabled: enabled)
    }

    var isWatchConnected: Bool { relayState.isConnected }
    var isSessionActivated: Bool { relayState.sessionActivated }
    var isWatchReachable: Bool { relayState.watchReachable }
    var isWatchPaired: Bool { relayState.watchPaired }
    var isWatchAppInstalled: Bool { relayState.watchAppInstalled }
    var messagesReceived: UInt { relayState.messagesReceived }
    var lastMessageAt: Date? { relayState.lastMessageAt }
    var lastPayload: MotionPayload? { relayState.lastPayload }
    var lastControlMessage: String? { relayState.lastControlMessage }
    var lastErrorDescription: String? { relayState.lastErrorDescription }
    var lastWatchError: String? { relayState.lastWatchError }
    var isBackgroundRelayActive: Bool { relayState.isBackgroundRelayActive }
    var statusSummary: String { relayState.statusSummary }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async {
            self.relayState.applyActivation(activationState, error: error)
            if error != nil {
                self.didRequestActivation = false
            }
            self.refreshFlags()
            self.macForwarder.ensureConnected()
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.refreshFlags()
        }
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.refreshFlags()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        DispatchQueue.main.async {
            self.relayState.applyReachability(false)
        }
    }

    func sessionDidDeactivate(_ session: WCSession) {
        DispatchQueue.main.async {
            self.relayState.applyReachability(false)
        }
        didRequestActivation = false
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleIncoming(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handleIncoming(userInfo)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handleIncoming(applicationContext)
    }

    private func handleIncoming(_ message: [String: Any]) {
        if UIApplication.shared.applicationState != .active {
            beginRelayBackgroundTask(reason: "WatchConnectivity delivery")
        }

        let type = message["type"] as? String

        // Errors mirrored from the Watch: surface in the companion UI only —
        // never forward them to the Mac cursor server.
        if type == "watch_error" {
            let msg = (message["message"] as? String) ?? "Watch reported an error"
            DispatchQueue.main.async { self.relayState.applyWatchError(msg) }
            return
        }

        DispatchQueue.main.async {
            if let payload = MotionPayload.fromDictionary(message) {
                self.relayState.recordMessage(payload)
            } else if type == "click" || (message["click"] as? NSNumber)?.boolValue == true {
                // Count clicks as activity too.
                self.relayState.recordControl("click")
            } else if let type {
                self.relayState.recordControl(type)
            } else {
                self.relayState.applyFailure(
                    component: "PhoneWatchReceiver.handleIncoming",
                    rootCause: "Watch message did not contain IMU fields or a known control type",
                    failureType: .invalidPayload
                )
            }
            self.relayState.applyReachability(self.session.isReachable)
        }

        macForwarder.ensureConnected()
        if type != "wake" {
            let isMotion = MotionPayload.fromDictionary(message) != nil
            let phoneSuppressesWatchPointer = macForwarder.phonePointerEngaged
                && (isMotion || type == "calib")
            if !phoneSuppressesWatchPointer {
                macForwarder.forwardMotion(message)
            }
            sensorDebugStreamer.send(message)
        }
    }

    private func installLifecycleObservers() {
        let center = NotificationCenter.default
        lifecycleObservers.append(
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                self?.beginRelayBackgroundTask(reason: "iPhone entered background")
                self?.macForwarder.ensureConnected()
            }
        )
        lifecycleObservers.append(
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                self?.activateSessionIfNeeded()
                self?.macForwarder.ensureConnected()
                self?.endRelayBackgroundTask()
            }
        )
        lifecycleObservers.append(
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                self?.activateSessionIfNeeded()
                self?.macForwarder.ensureConnected()
            }
        )
    }

    private func bindNestedState() {
        relayState.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        macForwarder.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    private func beginRelayBackgroundTask(reason: String) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.beginRelayBackgroundTask(reason: reason)
            }
            return
        }
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "PointerRelay") { [weak self] in
            self?.relayState.applyFailure(
                component: "PhoneWatchReceiver.backgroundTask",
                rootCause: "iOS expired the background relay window",
                failureType: .transportUnavailable
            )
            self?.endRelayBackgroundTask()
        }

        if backgroundTask == .invalid {
            relayState.applyFailure(
                component: "PhoneWatchReceiver.backgroundTask",
                rootCause: "iOS refused to start background relay task: \(reason)",
                failureType: .activationFailure
            )
        } else {
            relayState.isBackgroundRelayActive = true
        }
    }

    private func endRelayBackgroundTask() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.endRelayBackgroundTask()
            }
            return
        }
        guard backgroundTask != .invalid else { return }
        let task = backgroundTask
        backgroundTask = .invalid
        UIApplication.shared.endBackgroundTask(task)
        relayState.isBackgroundRelayActive = false
    }
}
#endif
