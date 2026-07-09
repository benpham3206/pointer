//
//  MacForwarder.swift
//  pointer
//

#if os(iOS)
import Foundation
import Network
import Combine

/// Discovers Mac pointer hosts via Bonjour and streams motion JSON lines over TCP.
/// Auto-reconnects aggressively when the Mac server restarts or the link drops.
final class MacForwarder: ObservableObject {
    static let bonjourType = "_pointer._tcp"

    enum ConnectionStatus: Equatable {
        case idle
        case browsing
        case connecting
        case connected(host: String)
        case disconnected
        case failed(String)
    }

    struct DiscoveredMac: Identifiable {
        let id: String
        let name: String
        let endpoint: NWEndpoint
    }

    @Published private(set) var status: ConnectionStatus = .idle
    @Published private(set) var discoveredMacs: [DiscoveredMac] = []
    @Published private(set) var selectedMacID: String?
    @Published private(set) var packetsForwarded: UInt = 0
    @Published private(set) var lastSendError: String?
    @Published private(set) var packetsQueued: Int = 0

    private let queue = DispatchQueue(label: "bp.pointer.macforwarder", qos: .userInitiated)
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var reconnectWorkItem: DispatchWorkItem?
    private var heartbeatTimer: DispatchSourceTimer?
    private var shouldStayConnected = false
    private var connectedDisplayName: String?
    private var pendingPackets: [Data] = []
    private let maxPendingPackets = 120

    init() {
        startBrowsing()
        startHeartbeat()
    }

    deinit {
        stopAll()
    }

    /// Call when the phone app becomes active again.
    func ensureConnected() {
        shouldStayConnected = true
        queue.async { [weak self] in
            guard let self else { return }
            if self.connection?.state == .ready { return }
            if self.browser == nil {
                DispatchQueue.main.async { self.startBrowsing() }
            } else {
                self.scheduleReconnect(after: 0.3)
            }
        }
    }

    func startBrowsing() {
        stopConnectionOnly()
        shouldStayConnected = true
        lastSendError = nil

        browser?.cancel()
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        let browser = NWBrowser(for: .bonjour(type: Self.bonjourType, domain: nil), using: parameters)
        self.browser = browser

        browser.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                guard let self else { return }
                switch state {
                case .ready:
                    if case .browsing = self.status { break }
                    if case .connected = self.status { break }
                    self.status = .browsing
                case .failed(let error):
                    self.status = .failed(error.localizedDescription)
                    self.scheduleReconnect(after: 2)
                case .cancelled:
                    if self.shouldStayConnected {
                        self.status = .disconnected
                        self.scheduleReconnect(after: 2)
                    }
                default:
                    break
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            let macs: [DiscoveredMac] = results.compactMap { result in
                guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                let id = "\(name)-\(result.endpoint.debugDescription)"
                return DiscoveredMac(id: id, name: name, endpoint: result.endpoint)
            }
            DispatchQueue.main.async {
                self.discoveredMacs = macs
                if self.selectedMacID == nil, let first = macs.first {
                    self.selectMac(first)
                } else if let selected = self.selectedMacID,
                          let match = macs.first(where: { $0.id == selected }) {
                    // Reconnect if not ready.
                    if self.connection?.state != .ready {
                        self.connect(to: match.endpoint, displayName: match.name)
                    }
                } else if let selected = self.selectedMacID,
                          macs.contains(where: { $0.id == selected }) == false {
                    self.selectedMacID = nil
                    if let first = macs.first {
                        self.selectMac(first)
                    } else {
                        self.stopConnectionOnly()
                        self.status = .browsing
                    }
                } else if self.selectedMacID == nil, let first = macs.first {
                    self.selectMac(first)
                }
            }
        }

        browser.start(queue: queue)
        DispatchQueue.main.async {
            if case .connected = self.status { return }
            self.status = .browsing
        }
    }

    func selectMac(_ mac: DiscoveredMac) {
        selectedMacID = mac.id
        connect(to: mac.endpoint, displayName: mac.name)
    }

    func selectMac(id: String) {
        guard let mac = discoveredMacs.first(where: { $0.id == id }) else { return }
        selectMac(mac)
    }

    func forwardMotion(_ payload: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(payload) else {
            applyFailure(
                component: "MacForwarder.forwardMotion",
                rootCause: "Payload is not valid JSON",
                failureType: .serializationFailed
            )
            return
        }

        var data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            applyFailure(
                component: "MacForwarder.forwardMotion",
                rootCause: error.localizedDescription,
                failureType: .serializationFailed
            )
            return
        }
        data.append(0x0A)

        queue.async { [weak self] in
            self?.enqueueOrSend(data)
        }
    }

    func stopAll() {
        shouldStayConnected = false
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        browser?.cancel()
        browser = nil
        connection?.cancel()
        connection = nil
        pendingPackets.removeAll()
        DispatchQueue.main.async {
            self.status = .idle
            self.discoveredMacs = []
            self.selectedMacID = nil
            self.packetsQueued = 0
        }
    }

    // MARK: - Private

    private func startHeartbeat() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 3, repeating: 3)
        timer.setEventHandler { [weak self] in
            guard let self, self.shouldStayConnected else { return }
            if self.connection?.state == .ready { return }
            // Not connected — browse / reconnect.
            if self.browser == nil {
                DispatchQueue.main.async { self.startBrowsing() }
            } else if let id = self.selectedMacID,
                      let mac = self.discoveredMacs.first(where: { $0.id == id }) {
                self.connect(to: mac.endpoint, displayName: mac.name)
            } else if let first = self.discoveredMacs.first {
                DispatchQueue.main.async { self.selectMac(first) }
            }
        }
        timer.resume()
        heartbeatTimer = timer
    }

    private func connect(to endpoint: NWEndpoint, displayName: String) {
        stopConnectionOnly()
        connectedDisplayName = displayName
        DispatchQueue.main.async { self.status = .connecting }

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let connection = NWConnection(to: endpoint, using: parameters)
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self.status = .connected(host: displayName)
                    self.lastSendError = nil
                    self.queue.async {
                        self.flushPendingPackets()
                    }
                case .failed(let error):
                    self.lastSendError = error.localizedDescription
                    self.status = .failed(error.localizedDescription)
                    self.connection = nil
                    self.scheduleReconnect(after: 1)
                case .cancelled:
                    if self.shouldStayConnected {
                        self.status = .disconnected
                        self.scheduleReconnect(after: 1)
                    }
                case .waiting(let error):
                    self.lastSendError = error.localizedDescription
                    self.scheduleReconnect(after: 2)
                default:
                    break
                }
            }
        }

        connection.start(queue: queue)
    }

    private func enqueueOrSend(_ data: Data) {
        guard connection?.state == .ready else {
            pendingPackets.append(data)
            if pendingPackets.count > maxPendingPackets {
                pendingPackets.removeFirst(pendingPackets.count - maxPendingPackets)
            }
            let queued = pendingPackets.count
            DispatchQueue.main.async {
                self.packetsQueued = queued
                self.lastSendError = "Queued \(queued) packet(s) waiting for Mac relay"
            }
            scheduleReconnect(after: 0.2)
            return
        }

        sendOnConnection(data)
    }

    private func flushPendingPackets() {
        guard connection?.state == .ready, !pendingPackets.isEmpty else { return }
        let packets = pendingPackets
        pendingPackets.removeAll()
        DispatchQueue.main.async {
            self.packetsQueued = 0
            self.lastSendError = nil
        }
        for packet in packets {
            sendOnConnection(packet)
        }
    }

    private func sendOnConnection(_ data: Data) {
        guard let connection else {
            enqueueOrSend(data)
            return
        }
        guard connection.state == .ready else {
            enqueueOrSend(data)
            return
        }

        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    self?.lastSendError = error.localizedDescription
                    self?.scheduleReconnect(after: 0.5)
                } else {
                    self?.packetsForwarded += 1
                }
            }
        })
    }

    private func stopConnectionOnly() {
        connection?.cancel()
        connection = nil
    }

    private func scheduleReconnect(after delay: TimeInterval) {
        guard shouldStayConnected else { return }
        reconnectWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.shouldStayConnected else { return }
            if self.connection?.state == .ready { return }
            if let id = self.selectedMacID,
               let mac = self.discoveredMacs.first(where: { $0.id == id }) {
                self.connect(to: mac.endpoint, displayName: mac.name)
            } else if let first = self.discoveredMacs.first {
                DispatchQueue.main.async { self.selectMac(first) }
            } else if self.browser == nil {
                DispatchQueue.main.async { self.startBrowsing() }
            } else {
                // Force browser refresh
                DispatchQueue.main.async {
                    self.browser?.cancel()
                    self.browser = nil
                    self.startBrowsing()
                }
            }
        }
        reconnectWorkItem = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func applyFailure(
        component: String,
        rootCause: String,
        failureType: PointerFailurePayload.FailureType
    ) {
        let failure = PointerFailurePayload(
            component: component,
            rootCause: rootCause,
            failureType: failureType
        )
        DispatchQueue.main.async {
            self.lastSendError = failure.description
        }
    }
}
#endif
