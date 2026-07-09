//
//  SensorDebugStreamer.swift
//  pointer
//
//  Optional TCP mirror of Watch IMU for Mac Python viewer (tools/watch_sensor_tracker.py).

#if os(iOS)
import Foundation
import Network

/// Forwards newline-delimited JSON motion to a Mac TCP listener (default port 19778).
final class SensorDebugStreamer {
    static let defaultPort: UInt16 = 19778

    private let queue = DispatchQueue(label: "bp.pointer.sensor-debug")
    private var connection: NWConnection?
    private var host: String = ""
    private var port: UInt16 = 19778
    private var enabled = false

    func configure(host: String, port: UInt16, enabled: Bool) {
        queue.async {
            let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
            let changed = self.host != trimmed || self.port != port || self.enabled != enabled
            self.host = trimmed
            self.port = port
            self.enabled = enabled
            if !enabled {
                self.teardown()
                return
            }
            if changed || self.connection == nil {
                self.reconnect()
            }
        }
    }

    func send(_ message: [String: Any]) {
        queue.async {
            guard self.enabled, self.connection != nil else { return }
            guard let data = try? JSONSerialization.data(withJSONObject: message),
                  var line = String(data: data, encoding: .utf8) else { return }
            line.append("\n")
            guard let out = line.data(using: .utf8) else { return }
            self.connection?.send(content: out, completion: .contentProcessed { _ in })
        }
    }

    private func reconnect() {
        teardown()
        guard enabled, !host.isEmpty else { return }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
        let conn = NWConnection(to: endpoint, using: .tcp)
        connection = conn
        conn.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.scheduleReconnect() }
            if case .cancelled = state { self?.connection = nil }
        }
        conn.start(queue: queue)
    }

    private func scheduleReconnect() {
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.enabled else { return }
            self.reconnect()
        }
    }

    private func teardown() {
        connection?.cancel()
        connection = nil
    }
}
#endif