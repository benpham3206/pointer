import CoreBluetooth
import Foundation

final class BLEPeripheralService: NSObject, CBPeripheralManagerDelegate {
    private static let serviceUUID = CBUUID(string: "E0B1C001-7A42-4E6A-9A4D-4F5E3A1C0001")
    private static let motionUUID = CBUUID(string: "E0B1C002-7A42-4E6A-9A4D-4F5E3A1C0001")
    private static let controlUUID = CBUUID(string: "E0B1C003-7A42-4E6A-9A4D-4F5E3A1C0001")

    private let onFrame: (PointerFrame) -> Void
    private weak var appState: AppState?
    private var peripheralManager: CBPeripheralManager?
    private var serviceRegistered = false
    private var motionCharacteristic: CBMutableCharacteristic?
    private var controlCharacteristic: CBMutableCharacteristic?

    init(onFrame: @escaping (PointerFrame) -> Void, appState: AppState) {
        self.onFrame = onFrame
        self.appState = appState
        super.init()
    }

    func start() {
        guard peripheralManager == nil else { return }
        appState?.setBLEState("off — starting")
        peripheralManager = CBPeripheralManager(delegate: self, queue: .main)
    }

    func stop() {
        peripheralManager?.stopAdvertising()
        if let peripheralManager {
            peripheralManager.removeAllServices()
            peripheralManager.delegate = nil
        }
        peripheralManager = nil
        serviceRegistered = false
        motionCharacteristic = nil
        controlCharacteristic = nil
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            appState?.setBLEState("starting service")
            publishServiceIfNeeded(on: peripheral)
        case .poweredOff:
            serviceRegistered = false
            appState?.setBLEState("off — Bluetooth powered off")
        case .unauthorized:
            appState?.setBLEState("off — permission denied")
            appState?.reportFailure(
                component: "BLEPeripheralService.state",
                rootCause: "Bluetooth permission is not granted to Pointer Mac",
                failureType: "permissionDenied"
            )
        case .unsupported:
            appState?.setBLEState("off — unsupported")
            appState?.reportFailure(
                component: "BLEPeripheralService.state",
                rootCause: "This Mac cannot advertise a Bluetooth LE service",
                failureType: "transportUnavailable"
            )
        case .resetting:
            serviceRegistered = false
            appState?.setBLEState("off — resetting")
        case .unknown:
            appState?.setBLEState("off — unavailable")
        @unknown default:
            appState?.setBLEState("off — unknown state")
            appState?.reportFailure(
                component: "BLEPeripheralService.state",
                rootCause: "CoreBluetooth returned an unknown peripheral state",
                failureType: "unknown"
            )
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error {
            serviceRegistered = false
            appState?.setBLEState("off — service failed")
            appState?.reportFailure(
                component: "BLEPeripheralService.didAddService",
                rootCause: error.localizedDescription,
                failureType: "serviceRegistrationFailed"
            )
            return
        }
        peripheral.startAdvertising([
            CBAdvertisementDataLocalNameKey: "Pointer Mac",
            CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID],
        ])
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            appState?.setBLEState("off — advertising failed")
            appState?.reportFailure(
                component: "BLEPeripheralService.didStartAdvertising",
                rootCause: error.localizedDescription,
                failureType: "advertisingFailed"
            )
            return
        }
        appState?.setBLEState("advertising")
        appState?.clearFailure(component: "BLEPeripheralService")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        guard let first = requests.first else { return }
        let valid = requests.allSatisfy { request in
            request.offset == 0
                && (request.characteristic.uuid == Self.motionUUID
                    || request.characteristic.uuid == Self.controlUUID)
                && request.value.map(PointerFrame.hasValidWireShape) == true
        }
        guard valid else {
            peripheral.respond(to: first, withResult: .invalidPdu)
            appState?.reportFailure(
                component: "BLEPeripheralService.didReceiveWrite",
                rootCause: "Watch sent an invalid Pointer frame",
                failureType: "invalidPayload"
            )
            return
        }

        for request in requests {
            guard let value = request.value else { continue }
            if KeyboardSynthesizer.handle(value) { continue }
            guard let frame = PointerFrame.decode(value) else { continue }
            onFrame(frame)
        }
        peripheral.respond(to: first, withResult: .success)
    }

    private func publishServiceIfNeeded(on peripheral: CBPeripheralManager) {
        guard !serviceRegistered else { return }
        serviceRegistered = true

        let motion = CBMutableCharacteristic(
            type: Self.motionUUID,
            properties: [.writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )
        let control = CBMutableCharacteristic(
            type: Self.controlUUID,
            properties: [.write],
            value: nil,
            permissions: [.writeable]
        )
        let service = CBMutableService(type: Self.serviceUUID, primary: true)
        service.characteristics = [motion, control]
        motionCharacteristic = motion
        controlCharacteristic = control
        peripheral.add(service)
    }
}
