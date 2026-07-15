import ApplicationServices
import CoreGraphics
import Foundation

struct PointerDisplay {
    let id: CGDirectDisplayID
    let isMain: Bool
    let bounds: CGRect

    var area: CGFloat { bounds.width * bounds.height }

    static func pick(mode: String) -> PointerDisplay {
        let displays = activeDisplays()
        guard !displays.isEmpty else {
            return PointerDisplay(
                id: 0,
                isMain: true,
                bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080)
            )
        }
        if mode == "main" {
            return displays.first(where: \.isMain) ?? displays[0]
        }
        if mode == "largest" {
            return displays.max(by: { $0.area < $1.area }) ?? displays[0]
        }
        let external = displays.filter { !$0.isMain }
        return external.max(by: { $0.area < $1.area })
            ?? displays.max(by: { $0.area < $1.area })
            ?? displays[0]
    }

    private static func activeDisplays() -> [PointerDisplay] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        let main = CGMainDisplayID()
        return ids.prefix(Int(count)).map {
            PointerDisplay(id: $0, isMain: $0 == main, bounds: CGDisplayBounds($0))
        }
    }
}

struct CursorFailure {
    let component: String
    let rootCause: String
    let failureType: String
}

final class CursorSynthesizer {
    func postMouseMove(to point: CGPoint) -> CursorFailure? {
        guard AXIsProcessTrusted() else {
            return CursorFailure(
                component: "CursorSynthesizer.postMouseMove",
                rootCause: "Pointer Mac is not trusted in Accessibility settings",
                failureType: "permissionDenied"
            )
        }
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            return CursorFailure(
                component: "CursorSynthesizer.postMouseMove",
                rootCause: "CoreGraphics could not create a mouse moved event",
                failureType: "eventCreationFailed"
            )
        }
        let warpResult = CGWarpMouseCursorPosition(point)
        guard warpResult == .success else {
            return CursorFailure(
                component: "CursorSynthesizer.postMouseMove",
                rootCause: "CoreGraphics could not warp the cursor (error \(warpResult.rawValue))",
                failureType: "eventPostFailed"
            )
        }
        event.post(tap: .cghidEventTap)
        return nil
    }

    func leftClick() -> CursorFailure? {
        click(downType: .leftMouseDown, upType: .leftMouseUp, button: .left, name: "leftClick")
    }

    func rightClick() -> CursorFailure? {
        click(downType: .rightMouseDown, upType: .rightMouseUp, button: .right, name: "rightClick")
    }

    private func click(
        downType: CGEventType,
        upType: CGEventType,
        button: CGMouseButton,
        name: String
    ) -> CursorFailure? {
        guard AXIsProcessTrusted() else {
            return CursorFailure(
                component: "CursorSynthesizer.\(name)",
                rootCause: "Pointer Mac is not trusted in Accessibility settings",
                failureType: "permissionDenied"
            )
        }
        guard let currentEvent = CGEvent(source: nil) else {
            return CursorFailure(
                component: "CursorSynthesizer.\(name)",
                rootCause: "CoreGraphics could not read the current cursor location",
                failureType: "unavailableResource"
            )
        }
        let point = currentEvent.location
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(
            mouseEventSource: source,
            mouseType: downType,
            mouseCursorPosition: point,
            mouseButton: button
        ), let up = CGEvent(
            mouseEventSource: source,
            mouseType: upType,
            mouseCursorPosition: point,
            mouseButton: button
        ) else {
            return CursorFailure(
                component: "CursorSynthesizer.\(name)",
                rootCause: "CoreGraphics could not create mouse down/up events",
                failureType: "eventCreationFailed"
            )
        }
        down.post(tap: .cghidEventTap)
        usleep(8_000)
        up.post(tap: .cghidEventTap)
        return nil
    }
}
