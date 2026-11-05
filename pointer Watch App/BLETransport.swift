//
//  BLETransport.swift
//  pointer Watch App
//

import Combine
import CoreBluetooth
import Foundation
import os

/// Direct Watch → Mac BLE transport. watchOS only supports the central role, so
/// the Mac advertises the GATT service and the Watch writes the existing frames.
/// Until both characteristics are ready, MotionManager keeps using the phone relay.
final class BLETransport: NSObject, ObservableObject {
    static let serviceUUID = CBUUID(string: "E0B1C001-7A42-4E6A-9A4D-4F5E3A1C0001")
    static let motionUUID = CBUUID(string: "E0B1C002-7A42-4E6A-9A4D-4F5E3A1C0001")
    static let controlUUID = CBUUID(string: "E0B1C003-7A42-4E6A-9A4D-4F5E3A1C0001")

    enum LinkState: String {
        case starting
        case scanning
        case connected
        case unavailable
    }

    struct Failure: CustomStringConvertible {
        let component: String
        let rootCause: String
        let failureType: String

        var description: String {
            "\(component) [\(failureType)]: \(rootCause)"
        }
    }

    @Published private(set) var linkState: LinkState = .starting
    @Published private(set) var isConnected = false

    var onLinkStateChanged: ((LinkState) -> Void)?
    var onFailure: ((Failure) -> Void)?

    private let log = Logger(subsystem: "bp.pointer.watch", category: "BLE")
    private var centralManager: CBCentralManager!
    private var macPeripheral: CBPeripheral?
    private var motionCharacteristic: CBCharacteristic?
    private var controlCharacteristic: CBCharacteristic?
    private var queuedControlFrames: [Data] = []
    private var controlWriteInFlight = false
    private var reconnectWorkItem: DispatchWorkItem?
    private var retryDelay: TimeInterval = 0.5
    private let maxQueuedControlFrames = 32

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    /// Returns true when BLE owns this motion frame. CoreBluetooth backpressure may
    /// drop motion; the next 15 Hz sample replaces it without delaying the cursor.
    @discardableResult
    func sendMotion(roll: Double, yaw: Double, pitch: Double) -> Bool {
        guard isConnected, let macPeripheral, let motionCharacteristic else { return false }
        guard macPeripheral.canSendWriteWithoutResponse else {
            log.debug("motion write buffer full; dropping frame")
            return true
        }
        macPeripheral.writeValue(
            Self.motionFrame(roll: roll, yaw: yaw, pitch: pitch),
            for: motionCharacteristic,
            type: .withoutResponse
        )
        return true
    }

    /// Returns true when BLE owns this control frame. Controls use acknowledged
    /// writes and remain queued until the Mac accepts each one.
    @discardableResult
    func sendControl(_ frame: Data) -> Bool {
        guard isConnected else { return false }
        queuedControlFrames.append(frame)
        if queuedControlFrames.count > maxQueuedControlFrames {
            let framesToDiscard = queuedControlFrames.count - maxQueuedControlFrames
            let firstDiscardableIndex = controlWriteInFlight ? 1 : 0
            queuedControlFrames.removeSubrange(
                firstDiscardableIndex..<(firstDiscardableIndex + framesToDiscard)
            )
            reportFailure(
                component: "BLETransport.sendControl",
                rootCause: "BLE control retry queue reached \(maxQueuedControlFrames) frames; oldest unsent frame was discarded",
                failureType: "backpressure"
            )
        }
        flushQueuedControls()
        return true
    }

    /// Shared verbatim wire format: type byte followed by little-endian Float32s.
    static func frame(for payload: [String: Any]) -> Data? {
        func float(_ key: String) -> Double {
            if let value = payload[key] as? Double { return value }
            if let value = payload[key] as? NSNumber { return value.doubleValue }
            return 0
        }

        let type = payload["type"] as? String
        if type == "text" {
            guard let text = payload["text"] as? String else { return nil }
            let bytes = Array(text.utf8)
            guard bytes.count <= 255 else { return nil }
            return Data([0x06, UInt8(bytes.count)] + bytes)
        }
        if type == "key" {
            guard let keycode = (payload["keycode"] as? NSNumber)?.intValue,
                  let modifiers = (payload["modifiers"] as? NSNumber)?.intValue,
                  let action = (payload["action"] as? NSNumber)?.intValue,
                  (0...Int(UInt16.max)).contains(keycode),
                  (0...Int(UInt8.max)).contains(modifiers),
                  (0...2).contains(action)
            else { return nil }
            return Data([
                0x07,
                UInt8(keycode & 0xFF),
                UInt8((keycode >> 8) & 0xFF),
                UInt8(modifiers),
                UInt8(action),
            ])
        }
        guard type == nil
                || type == "click"
                || type == "calib_clear"
                || type == "reset"
                || type == "calib"
        else { return nil }
        if type == "click" || (payload["click"] as? NSNumber)?.boolValue == true {
            return Data([0x02])
        }
        if type == "calib_clear" { return Data([0x04]) }
        if type == "reset" { return Data([0x05]) }
        if type == "calib" {
            let corners: [String: UInt8] = ["tl": 0, "tr": 1, "bl": 2, "br": 3]
            return floats(
                prefix: [0x03, corners[(payload["corner"] as? String) ?? ""] ?? 0],
                values: [float("roll"), float("yaw"), float("pitch")]
            )
        }
        guard type == nil else { return nil }
        guard payload["roll"] != nil, payload["yaw"] != nil else { return nil }
        return motionFrame(roll: float("roll"), yaw: float("yaw"), pitch: float("pitch"))
    }

    private static func motionFrame(roll: Double, yaw: Double, pitch: Double) -> Data {
        floats(prefix: [0x01], values: [roll, yaw, pitch])
    }

    private static func floats(prefix: [UInt8], values: [Double]) -> Data {
        var data = Data(prefix)
        for value in values {
            var bits = Float(value).bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        return data
    }

    private func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        reconnectWorkItem?.cancel()
        centralManager.stopScan()
        centralManager.scanForPeripherals(withServices: [Self.serviceUUID], options: nil)
        setLinkState(.scanning)
        log.notice("BLE scanning for Mac")
    }

    private func disconnectAndRetry(after delay: TimeInterval) {
        isConnected = false
        setLinkState(.scanning)
        motionCharacteristic = nil
        controlCharacteristic = nil
        controlWriteInFlight = false
        if let macPeripheral {
            centralManager.cancelPeripheralConnection(macPeripheral)
        }
        macPeripheral = nil
        reconnectWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.startScanning()
        }
        reconnectWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func flushQueuedControls() {
        guard !controlWriteInFlight,
              isConnected,
              let macPeripheral,
              let controlCharacteristic,
              let frame = queuedControlFrames.first
        else { return }
        controlWriteInFlight = true
        macPeripheral.writeValue(frame, for: controlCharacteristic, type: .withResponse)
    }

    private func setLinkState(_ state: LinkState) {
        guard linkState != state else { return }
        linkState = state
        onLinkStateChanged?(state)
    }

    private func reportFailure(component: String, rootCause: String, failureType: String) {
        let failure = Failure(component: component, rootCause: rootCause, failureType: failureType)
        log.error("\(failure.description, privacy: .public)")
        onFailure?(failure)
    }
}

extension BLETransport: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            retryDelay = 0.5
            startScanning()
        case .poweredOff:
            isConnected = false
            setLinkState(.unavailable)
            reportFailure(
                component: "BLETransport.centralManagerDidUpdateState",
                rootCause: "Bluetooth is powered off; using the iPhone relay",
                failureType: "transportUnavailable"
            )
        case .unauthorized:
            isConnected = false
            setLinkState(.unavailable)
            reportFailure(
                component: "BLETransport.centralManagerDidUpdateState",
                rootCause: "Bluetooth permission is not granted; using the iPhone relay",
                failureType: "permissionDenied"
            )
        case .unsupported:
            isConnected = false
            setLinkState(.unavailable)
            reportFailure(
                component: "BLETransport.centralManagerDidUpdateState",
                rootCause: "This Watch does not support Bluetooth LE central mode; using the iPhone relay",
                failureType: "transportUnavailable"
            )
        case .resetting, .unknown:
            isConnected = false
            setLinkState(.starting)
        @unknown default:
            isConnected = false
            setLinkState(.unavailable)
            reportFailure(
                component: "BLETransport.centralManagerDidUpdateState",
                rootCause: "Bluetooth reported an unknown state; using the iPhone relay",
                failureType: "unknown"
            )
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard macPeripheral == nil else { return }
        central.stopScan()
        macPeripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
        log.notice("BLE Mac discovered; connecting")
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        retryDelay = 0.5
        peripheral.delegate = self
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        reportFailure(
            component: "BLETransport.didFailToConnect",
            rootCause: error?.localizedDescription ?? "The Mac rejected the BLE connection",
            failureType: "connectionFailure"
        )
        disconnectAndRetry(after: retryDelay)
        retryDelay = min(retryDelay * 2, 10)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let error {
            reportFailure(
                component: "BLETransport.didDisconnect",
                rootCause: error.localizedDescription,
                failureType: "connectionFailure"
            )
        }
        disconnectAndRetry(after: retryDelay)
        retryDelay = min(retryDelay * 2, 10)
        log.notice("BLE Mac disconnected; falling back to iPhone relay")
    }
}

extension BLETransport: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            reportFailure(
                component: "BLETransport.didDiscoverServices",
                rootCause: error.localizedDescription,
                failureType: "serviceDiscoveryFailed"
            )
            disconnectAndRetry(after: retryDelay)
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            reportFailure(
                component: "BLETransport.didDiscoverServices",
                rootCause: "Mac did not expose the Pointer BLE service",
                failureType: "serviceDiscoveryFailed"
            )
            disconnectAndRetry(after: retryDelay)
            return
        }
        peripheral.discoverCharacteristics([Self.motionUUID, Self.controlUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            reportFailure(
                component: "BLETransport.didDiscoverCharacteristics",
                rootCause: error.localizedDescription,
                failureType: "characteristicDiscoveryFailed"
            )
            disconnectAndRetry(after: retryDelay)
            return
        }
        motionCharacteristic = service.characteristics?.first(where: { $0.uuid == Self.motionUUID })
        controlCharacteristic = service.characteristics?.first(where: { $0.uuid == Self.controlUUID })
        guard motionCharacteristic != nil, controlCharacteristic != nil else {
            reportFailure(
                component: "BLETransport.didDiscoverCharacteristics",
                rootCause: "Mac Pointer BLE service is missing motion or control",
                failureType: "characteristicDiscoveryFailed"
            )
            disconnectAndRetry(after: retryDelay)
            return
        }
        isConnected = true
        setLinkState(.connected)
        log.notice("BLE connected to Mac")
        flushQueuedControls()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.controlUUID else { return }
        controlWriteInFlight = false
        if let error {
            reportFailure(
                component: "BLETransport.didWriteControl",
                rootCause: error.localizedDescription,
                failureType: "controlDeliveryFailed"
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.flushQueuedControls()
            }
            return
        }
        if !queuedControlFrames.isEmpty {
            queuedControlFrames.removeFirst()
        }
        flushQueuedControls()
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        log.debug("BLE motion write buffer ready")
    }
}
