import Foundation

public struct CBUUID: Hashable {
    public let uuidString: String
    public init(string: String) { self.uuidString = string }
}

public enum CBManagerState { case unknown, resetting, unsupported, unauthorized, poweredOff, poweredOn }
public enum CBCharacteristicWriteType { case withResponse, withoutResponse }
public protocol CBCentralManagerDelegate: AnyObject {}
public protocol CBPeripheralDelegate: AnyObject {}

public final class CBCharacteristic {
    public let uuid: CBUUID
    public init(uuid: CBUUID) { self.uuid = uuid }
}

public final class CBService {
    public let uuid: CBUUID
    public var characteristics: [CBCharacteristic]?
    public init(uuid: CBUUID, characteristics: [CBCharacteristic]? = nil) {
        self.uuid = uuid
        self.characteristics = characteristics
    }
}

public final class CBPeripheral {
    public weak var delegate: CBPeripheralDelegate?
    public var services: [CBService]?
    public var canSendWriteWithoutResponse = true
    public private(set) var recordedWrites: [Data] = []
    public init() {}
    public func discoverServices(_ serviceUUIDs: [CBUUID]?) {}
    public func discoverCharacteristics(_ characteristicUUIDs: [CBUUID]?, for service: CBService) {}
    public func writeValue(_ data: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType) {
        recordedWrites.append(data)
    }
}

public final class CBCentralManager {
    public let state: CBManagerState = .poweredOn
    public weak var delegate: CBCentralManagerDelegate?
    public init(delegate: CBCentralManagerDelegate?, queue: DispatchQueue?) { self.delegate = delegate }
    public func stopScan() {}
    public func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]?) {}
    public func connect(_ peripheral: CBPeripheral, options: [String: Any]?) {}
    public func cancelPeripheralConnection(_ peripheral: CBPeripheral) {}
}
