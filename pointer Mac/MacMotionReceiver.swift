//
//  MacMotionReceiver.swift
//  pointer Mac
//

import Foundation
import Network
import Combine

/// Listens for iPhone-forwarded motion over Bonjour (`_pointer._tcp`) and feeds `MouseController`.
final class MacMotionReceiver: ObservableObject {
    static let bonjourType = "_pointer._tcp"
    static let bonjourDomain = "local."
    static let serviceName = "pointer"

    @Published private(set) var isListening = false
    @Published private(set) var activeConnections = 0
    @Published private(set) var statusMessage = "Idle"
    @Published private(set) var lastReceiveError: String?
    @Published private(set) var lastControlMessage: String?

    private let mouseController: MouseController
    private let queue = DispatchQueue(label: "bp.pointer.mac.motion-receiver", qos: .userInitiated)
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var receiveBuffers: [ObjectIdentifier: Data] = [:]

    init(mouseController: MouseController) {
        self.mouseController = mouseController
    }

    func start() {
        queue.async { [weak self] in
            self?.startOnQueue()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopOnQueue()
        }
    }

    private func startOnQueue() {
        guard listener == nil else { return }

        do {
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true
            parameters.acceptLocalOnly = false

            let listener = try NWListener(using: parameters)
            listener.service = NWListener.Service(
                name: Self.serviceName,
                type: Self.bonjourType,
                domain: Self.bonjourDomain
            )

            listener.stateUpdateHandler = { [weak self] state in
                self?.handleListenerState(state)
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }

            listener.start(queue: queue)
            self.listener = listener
        } catch {
            publishMain {
                self.isListening = false
                self.statusMessage = "Failed to start listener"
                self.lastReceiveError = error.localizedDescription
            }
        }
    }

    private func stopOnQueue() {
        listener?.cancel()
        listener = nil
        for connection in connections.values {
            connection.cancel()
        }
        connections.removeAll()
        receiveBuffers.removeAll()
        publishMain {
            self.isListening = false
            self.activeConnections = 0
            self.mouseController.isConnected = false
            self.statusMessage = "Stopped"
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            publishMain {
                self.isListening = true
                self.statusMessage = "Advertising \(Self.serviceName).\(Self.bonjourType)"
                self.lastReceiveError = nil
            }
        case .failed(let error):
            publishMain {
                self.isListening = false
                self.statusMessage = "Listener failed"
                self.lastReceiveError = error.localizedDescription
            }
        case .cancelled:
            publishMain {
                self.isListening = false
                self.statusMessage = "Listener cancelled"
            }
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        receiveBuffers[id] = Data()

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.publishMain {
                    self.activeConnections = self.connections.count
                    self.mouseController.isConnected = true
                    self.statusMessage = "Client connected"
                }
                self.receiveNext(on: connection)
            case .failed, .cancelled:
                self.teardownConnection(id)
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func teardownConnection(_ id: ObjectIdentifier) {
        connections.removeValue(forKey: id)
        receiveBuffers.removeValue(forKey: id)
        publishMain {
            self.activeConnections = self.connections.count
            self.mouseController.isConnected = self.activeConnections > 0
            if self.activeConnections == 0 {
                self.statusMessage = self.isListening ? "Waiting for iPhone" : "Idle"
                self.mouseController.resetDeltas()
            }
        }
    }

    private func receiveNext(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                self.publishMain {
                    self.lastReceiveError = error.localizedDescription
                }
                self.teardownConnection(ObjectIdentifier(connection))
                return
            }

            if let data, !data.isEmpty {
                self.appendAndParse(data, connection: connection)
            }

            if isComplete {
                self.teardownConnection(ObjectIdentifier(connection))
            } else {
                self.receiveNext(on: connection)
            }
        }
    }

    private func appendAndParse(_ chunk: Data, connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        var buffer = receiveBuffers[id] ?? Data()
        buffer.append(chunk)
        receiveBuffers[id] = buffer

        while let (object, remainder) = Self.extractNextJSONObject(from: buffer) {
            buffer = remainder
            receiveBuffers[id] = buffer
            dispatchMotionPayload(object)
        }
    }

    /// Supports newline-delimited JSON objects (one motion frame per line).
    private static func extractNextJSONObject(from data: Data) -> ([String: Any], Data)? {
        guard let newlineIndex = data.firstIndex(of: 0x0A) else {
            if let object = tryParseJSONObject(data), !data.isEmpty {
                return (object, Data())
            }
            return nil
        }

        let lineData = data[..<newlineIndex]
        var remainder = Data(data[(data.index(after: newlineIndex))...])

        if let object = tryParseJSONObject(lineData) {
            return (object, remainder)
        }

        remainder = Data(data[(data.index(after: newlineIndex))...])
        return nil
    }

    private static func tryParseJSONObject(_ data: Data) -> [String: Any]? {
        guard !data.isEmpty else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return json as? [String: Any]
    }

    private func dispatchMotionPayload(_ payload: [String: Any]) {
        publishMain {
            if let type = payload["type"] as? String {
                self.lastControlMessage = type
            } else if (payload["click"] as? NSNumber)?.boolValue == true {
                self.lastControlMessage = "click"
            }

            if let failure = self.mouseController.processMessage(payload) {
                self.lastReceiveError = failure.description
            } else {
                self.lastReceiveError = nil
            }
        }
    }

    private func publishMain(_ block: @escaping () -> Void) {
        DispatchQueue.main.async(execute: block)
    }
}
