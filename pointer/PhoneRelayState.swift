//
//  PhoneRelayState.swift
//  pointer (iOS)
//

#if os(iOS)
import Combine
import Foundation
import WatchConnectivity

/// Published relay / watch link status for the iOS companion UI.
final class PhoneRelayState: ObservableObject {
    @Published var sessionActivated: Bool = false
    @Published var watchReachable: Bool = false
    @Published var watchPaired: Bool = false
    @Published var watchAppInstalled: Bool = false
    @Published var lastPayload: MotionPayload?
    @Published var messagesReceived: UInt = 0
    @Published var lastErrorDescription: String?
    @Published var lastMessageAt: Date?
    @Published var lastControlMessage: String?
    @Published var isBackgroundRelayActive: Bool = false

    /// True if we are actively receiving samples, or WCSession says reachable.
    var isConnected: Bool {
        if watchReachable { return true }
        if let t = lastMessageAt, Date().timeIntervalSince(t) < 2.5 { return true }
        return false
    }

    var statusSummary: String {
        if isConnected { return "Watch live" }
        if watchPaired && watchAppInstalled { return "Watch paired (open app on wrist)" }
        if watchPaired { return "Watch paired (install Watch app)" }
        if sessionActivated { return "No Watch paired" }
        return "WCSession inactive"
    }

    func applyActivation(_ state: WCSessionActivationState, error: Error?) {
        sessionActivated = (state == .activated)
        lastErrorDescription = error?.localizedDescription
    }

    func applyReachability(_ reachable: Bool) {
        watchReachable = reachable
    }

    func applySessionFlags(paired: Bool, appInstalled: Bool) {
        watchPaired = paired
        watchAppInstalled = appInstalled
    }

    func recordMessage(_ payload: MotionPayload) {
        lastPayload = payload
        messagesReceived &+= 1
        lastMessageAt = Date()
    }

    func recordControl(_ type: String) {
        lastControlMessage = type
        messagesReceived &+= 1
        lastMessageAt = Date()
    }

    func applyFailure(
        component: String,
        rootCause: String,
        failureType: PointerFailurePayload.FailureType
    ) {
        let failure = PointerFailurePayload(
            component: component,
            rootCause: rootCause,
            failureType: failureType
        )
        lastErrorDescription = failure.description
    }
}
#endif
