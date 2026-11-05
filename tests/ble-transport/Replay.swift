import Foundation
import CoreBluetooth

extension BLETransport {
    var queuedControlHeadForReplay: Data? { queuedControlFrames.first }
}

@main
struct Replay {
    static func main() {
        var failed = false

        let link = BLETransport()
        let central = CBCentralManager(delegate: nil, queue: nil)
        let peripheral = CBPeripheral()
        makeReady(link, central: central, peripheral: peripheral)
        link.centralManager(central, didDisconnectPeripheral: peripheral, error: nil)
        if !link.isConnected && link.linkState == .scanning {
            print("PASS disconnect clears the connected pill immediately")
        } else {
            print("FAIL disconnect state: isConnected=\(link.isConnected), linkState=\(link.linkState.rawValue), expected=false/scanning")
            failed = true
        }

        let queueLink = BLETransport()
        let queueCentral = CBCentralManager(delegate: nil, queue: nil)
        let queuePeripheral = CBPeripheral()
        makeReady(queueLink, central: queueCentral, peripheral: queuePeripheral)
        var overflowReported = false
        queueLink.onFailure = { failure in
            if failure.failureType == "backpressure" { overflowReported = true }
        }
        for value in 1...33 {
            queueLink.sendControl(Data([UInt8(value)]))
        }

        let firstWrite = queuePeripheral.recordedWrites.first
        let queueHeadBeforeAck = queueLink.queuedControlHeadForReplay
        if firstWrite == Data([1]), queueHeadBeforeAck == firstWrite {
            print("PASS overflow keeps the in-flight control at the queue head")
        } else {
            print("FAIL overflow state: firstWrite=\(firstWrite?.first.map(String.init) ?? "nil"), queueHead=\(queueHeadBeforeAck?.first.map(String.init) ?? "nil"), expected=1/1")
            failed = true
        }

        queueLink.peripheral(
            queuePeripheral,
            didWriteValueFor: CBCharacteristic(uuid: BLETransport.controlUUID),
            error: nil
        )
        let nextWrite = queuePeripheral.recordedWrites.last
        let queueHeadAfterAck = queueLink.queuedControlHeadForReplay
        if nextWrite == Data([3]), queueHeadAfterAck == nextWrite, overflowReported {
            print("PASS acknowledgement removes the written control and advances to the next retained control")
        } else {
            print("FAIL acknowledgement state: nextWrite=\(nextWrite?.first.map(String.init) ?? "nil"), queueHead=\(queueHeadAfterAck?.first.map(String.init) ?? "nil"), overflowReported=\(overflowReported), expected=3/3/true")
            failed = true
        }

        if failed {
            exit(EXIT_FAILURE)
        }
        print("PASS all BLE transport regression checks")
    }

    static func makeReady(_ transport: BLETransport, central: CBCentralManager, peripheral: CBPeripheral) {
        let service = CBService(
            uuid: BLETransport.serviceUUID,
            characteristics: [
                CBCharacteristic(uuid: BLETransport.motionUUID),
                CBCharacteristic(uuid: BLETransport.controlUUID),
            ]
        )
        peripheral.services = [service]
        transport.centralManager(central, didDiscover: peripheral, advertisementData: [:], rssi: 0)
        transport.centralManager(central, didConnect: peripheral)
        transport.peripheral(peripheral, didDiscoverServices: nil)
        transport.peripheral(peripheral, didDiscoverCharacteristicsFor: service, error: nil)
    }
}
