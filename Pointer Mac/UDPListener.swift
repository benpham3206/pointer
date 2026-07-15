import Foundation
import Network

enum PointerFrame {
    case motion(roll: Double, yaw: Double, pitch: Double)
    case click
    case rightClick
    case calibration(corner: String, roll: Double, yaw: Double, pitch: Double)
    case calibrationClear
    case reset
    case sourceClaim(source: PointerSource, active: Bool)

    static func hasValidWireShape(_ data: Data) -> Bool {
        guard let type = data.first else { return false }
        switch type {
        case 0x01: return data.count == 13
        case 0x02, 0x04, 0x05, 0x09: return data.count == 1
        case 0x03: return data.count == 14
        case 0x06: return data.count >= 2 && data.count == 2 + Int(data[1])
        case 0x07: return data.count == 5
        case 0x08: return data.count == 3
        default: return false
        }
    }

    static func decode(_ data: Data) -> PointerFrame? {
        guard hasValidWireShape(data), let type = data.first else { return nil }
        switch type {
        case 0x01:
            return .motion(
                roll: Double(data.float32LE(at: 1)),
                yaw: Double(data.float32LE(at: 5)),
                pitch: Double(data.float32LE(at: 9))
            )
        case 0x02:
            return .click
        case 0x09:
            return .rightClick
        case 0x03:
            let corners = ["tl", "tr", "bl", "br"]
            let index = Int(data[data.startIndex + 1])
            guard corners.indices.contains(index) else { return nil }
            return .calibration(
                corner: corners[index],
                roll: Double(data.float32LE(at: 2)),
                yaw: Double(data.float32LE(at: 6)),
                pitch: Double(data.float32LE(at: 10))
            )
        case 0x04:
            return .calibrationClear
        case 0x05:
            return .reset
        case 0x08:
            guard let source = PointerSource(wireValue: data[data.startIndex + 1]),
                  data[data.startIndex + 2] <= 1
            else { return nil }
            return .sourceClaim(source: source, active: data[data.startIndex + 2] == 1)
        default:
            return nil
        }
    }
}

extension PointerSource {
    init?(wireValue: UInt8) {
        switch wireValue {
        case 0: self = .watch
        case 1: self = .phone
        default: return nil
        }
    }
}

private extension Data {
    func float32LE(at offset: Int) -> Float {
        let start = startIndex + offset
        let bits = UInt32(self[start])
            | (UInt32(self[start + 1]) << 8)
            | (UInt32(self[start + 2]) << 16)
            | (UInt32(self[start + 3]) << 24)
        return Float(bitPattern: bits)
    }
}

final class UDPListener {
    private static let port: NWEndpoint.Port = 19790

    private let onFrame: (PointerFrame) -> Void
    private weak var appState: AppState?
    private var listener: NWListener?
    private var connections: [NWConnection] = []

    init(onFrame: @escaping (PointerFrame) -> Void, appState: AppState) {
        self.onFrame = onFrame
        self.appState = appState
    }

    func start() {
        do {
            let listener = try NWListener(using: .udp, on: Self.port)
            listener.service = NWListener.Service(name: "pointer", type: "_pointer._udp")
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.appState?.setUDPState("listening :19790")
                    self.appState?.clearFailure(component: "UDPListener.bind")
                case let .failed(error):
                    self.appState?.setUDPState("failed :19790")
                    self.appState?.reportFailure(
                        component: "UDPListener.bind",
                        rootCause: "Could not bind UDP :19790 (\(error)); the Python server may still be running",
                        failureType: "networkBindFailure"
                    )
                    self.stop()
                case .cancelled:
                    if self.appState?.udpState.hasPrefix("failed") != true {
                        self.appState?.setUDPState("off")
                    }
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            self.listener = listener
            listener.start(queue: .main)
        } catch {
            appState?.setUDPState("failed :19790")
            appState?.reportFailure(
                component: "UDPListener.start",
                rootCause: "Could not create UDP listener on :19790 (\(error)); the Python server may still be running",
                failureType: "networkBindFailure"
            )
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
    }

    private func accept(_ connection: NWConnection) {
        connections.append(connection)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            if case .failed = state { self.remove(connection) }
            if case .cancelled = state { self.remove(connection) }
        }
        connection.start(queue: .main)
        receive(from: connection)
    }

    private func receive(from connection: NWConnection) {
        connection.receiveMessage { [weak self, weak connection] data, _, _, error in
            guard let self, let connection else { return }
            if let data, KeyboardSynthesizer.handle(data) {
                // keyboard frame consumed (0x06 text / 0x07 key)
            } else if let data, let frame = PointerFrame.decode(data) {
                self.onFrame(frame)
            }
            if error == nil {
                self.receive(from: connection)
            } else {
                self.remove(connection)
            }
        }
    }

    private func remove(_ connection: NWConnection) {
        connections.removeAll { $0 === connection }
        connection.cancel()
    }
}
