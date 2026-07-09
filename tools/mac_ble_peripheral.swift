#!/usr/bin/env swift
import CoreBluetooth
import Foundation
import Network

private let serviceUUID = CBUUID(string: "E0B1C001-7A42-4E6A-9A4D-4F5E3A1C0001")
private let motionUUID = CBUUID(string: "E0B1C002-7A42-4E6A-9A4D-4F5E3A1C0001")
private let controlUUID = CBUUID(string: "E0B1C003-7A42-4E6A-9A4D-4F5E3A1C0001")

private func emitFailure(component: String, rootCause: String, failureType: String) {
    let payload: [String: String] = [
        "component": component,
        "rootCause": rootCause,
        "failureType": failureType,
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: payload),
          let text = String(data: data, encoding: .utf8)
    else {
        print("failure {\"component\":\"mac_ble_peripheral\",\"failureType\":\"serializationFailure\"}")
        return
    }
    print("failure \(text)")
}

private func isPointerFrame(_ data: Data) -> Bool {
    guard let type = data.first else { return false }
    switch type {
    case 0x01: return data.count == 13
    case 0x02, 0x04, 0x05: return data.count == 1
    case 0x03: return data.count == 14
    default: return false
    }
}

/// Publishes the Mac GATT service, then sends exact Watch frame bytes to the
/// Python server's existing localhost UDP input. watchOS supports the central
/// role but not a peripheral manager, so the roles are intentionally reversed.
private final class PointerBLEPeripheral: NSObject, CBPeripheralManagerDelegate {
    private let udp: NWConnection
    private var peripheralManager: CBPeripheralManager!
    private var serviceRegistered = false
    private var motionCharacteristic: CBMutableCharacteristic?
    private var controlCharacteristic: CBMutableCharacteristic?
    private var framesReceived = 0
    private var lastHeartbeat = Date.distantPast

    init(port: UInt16) {
        guard let udpPort = NWEndpoint.Port(rawValue: port) else {
            fatalError("invalid UDP port")
        }
        udp = NWConnection(host: "127.0.0.1", port: udpPort, using: .udp)
        super.init()
        udp.start(queue: .main)
        peripheralManager = CBPeripheralManager(delegate: self, queue: .main)
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            publishServiceIfNeeded()
        case .poweredOff:
            serviceRegistered = false
            emitFailure(
                component: "mac_ble_peripheral.state",
                rootCause: "Bluetooth is powered off; the Watch will use the iPhone relay",
                failureType: "transportUnavailable"
            )
        case .unauthorized:
            emitFailure(
                component: "mac_ble_peripheral.state",
                rootCause: "Bluetooth permission is not granted to the Mac BLE helper",
                failureType: "permissionDenied"
            )
        case .unsupported:
            emitFailure(
                component: "mac_ble_peripheral.state",
                rootCause: "This Mac cannot advertise a Bluetooth LE service",
                failureType: "transportUnavailable"
            )
        case .resetting, .unknown:
            break
        @unknown default:
            emitFailure(
                component: "mac_ble_peripheral.state",
                rootCause: "CoreBluetooth returned an unknown peripheral state",
                failureType: "unknown"
            )
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error {
            serviceRegistered = false
            emitFailure(
                component: "mac_ble_peripheral.didAddService",
                rootCause: error.localizedDescription,
                failureType: "serviceRegistrationFailed"
            )
            return
        }
        peripheral.startAdvertising([
            CBAdvertisementDataLocalNameKey: "Pointer Mac",
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
        ])
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            emitFailure(
                component: "mac_ble_peripheral.didStartAdvertising",
                rootCause: error.localizedDescription,
                failureType: "advertisingFailed"
            )
            return
        }
        print("BLE advertising Pointer Mac")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        guard let first = requests.first else { return }
        let valid = requests.allSatisfy { request in
            request.offset == 0
                && (request.characteristic.uuid == motionUUID || request.characteristic.uuid == controlUUID)
                && request.value.map(isPointerFrame) == true
        }
        guard valid else {
            peripheral.respond(to: first, withResult: .invalidPdu)
            emitFailure(
                component: "mac_ble_peripheral.didReceiveWrite",
                rootCause: "Watch sent an invalid Pointer frame",
                failureType: "invalidPayload"
            )
            return
        }

        for request in requests {
            guard let value = request.value else { continue }
            udp.send(content: value, completion: .contentProcessed { error in
                if let error {
                    emitFailure(
                        component: "mac_ble_peripheral.forwardUDP",
                        rootCause: error.localizedDescription,
                        failureType: "forwardingFailed"
                    )
                }
            })
            if value.first == 0x01 {
                framesReceived += 1
                let now = Date()
                if now.timeIntervalSince(lastHeartbeat) >= 2 {
                    print("BLE frames \(framesReceived) received")
                    lastHeartbeat = now
                }
            }
        }
        peripheral.respond(to: first, withResult: .success)
    }

    private func publishServiceIfNeeded() {
        guard !serviceRegistered else { return }
        serviceRegistered = true
        let motion = CBMutableCharacteristic(
            type: motionUUID,
            properties: [.writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )
        let control = CBMutableCharacteristic(
            type: controlUUID,
            properties: [.write],
            value: nil,
            permissions: [.writeable]
        )
        let service = CBMutableService(type: serviceUUID, primary: true)
        service.characteristics = [motion, control]
        motionCharacteristic = motion
        controlCharacteristic = control
        peripheralManager.add(service)
    }
}

func portFromArguments() -> UInt16? {
    guard let index = CommandLine.arguments.firstIndex(of: "--port"),
          CommandLine.arguments.indices.contains(index + 1),
          let port = UInt16(CommandLine.arguments[index + 1])
    else { return nil }
    return port
}

guard let port = portFromArguments() else {
    emitFailure(
        component: "mac_ble_peripheral.startup",
        rootCause: "Usage: mac_ble_peripheral.swift --port <udp-port>",
        failureType: "invalidConfiguration"
    )
    exit(2)
}

private let bridge = PointerBLEPeripheral(port: port)
RunLoop.main.run()
