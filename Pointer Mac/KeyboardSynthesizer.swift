import ApplicationServices
import CoreGraphics
import Foundation

enum SpecialKey {
    static let returnKey: CGKeyCode = 0x24
    static let delete: CGKeyCode = 0x33
    static let space: CGKeyCode = 0x31
    static let escape: CGKeyCode = 0x35
    static let tab: CGKeyCode = 0x30
    static let leftArrow: CGKeyCode = 0x7B
    static let rightArrow: CGKeyCode = 0x7C
    static let downArrow: CGKeyCode = 0x7D
    static let upArrow: CGKeyCode = 0x7E
}

enum KeyboardSynthesizer {
    struct Failure: Error, CustomStringConvertible {
        let component: String
        let rootCause: String
        let failureType: String

        var description: String {
            "{component: \(component), rootCause: \(rootCause), failureType: \(failureType)}"
        }
    }

    enum Command {
        case text(String)
        case key(code: CGKeyCode, modifiers: CGEventFlags, action: UInt8)
    }

    /// Decodes and executes keyboard frames. Returns false only for non-keyboard frames.
    @discardableResult
    static func handle(_ frame: Data) -> Bool {
        guard let type = frame.first, type == 0x06 || type == 0x07 else { return false }
        do {
            let command = try decode(frame)
            try execute(command)
        } catch let failure as Failure {
            NSLog("KeyboardSynthesizer failure: %@", failure.description)
        } catch {
            NSLog(
                "KeyboardSynthesizer failure: %@",
                Failure(
                    component: "KeyboardSynthesizer.handle",
                    rootCause: error.localizedDescription,
                    failureType: "unknown"
                ).description
            )
        }
        return true
    }

    static func decode(_ frame: Data) throws -> Command {
        let bytes = [UInt8](frame)
        switch bytes[0] {
        case 0x06:
            guard bytes.count >= 2 else {
                throw malformed("TEXT frame is missing its length byte")
            }
            let length = Int(bytes[1])
            guard bytes.count == length + 2 else {
                throw malformed("TEXT frame length is \(length), but payload contains \(bytes.count - 2) bytes")
            }
            guard let text = String(bytes: bytes.dropFirst(2), encoding: .utf8) else {
                throw malformed("TEXT payload is not valid UTF-8")
            }
            return .text(text)

        case 0x07:
            guard bytes.count == 5 else {
                throw malformed("KEY frame must contain exactly 5 bytes; received \(bytes.count)")
            }
            let keyCode = CGKeyCode(UInt16(bytes[1]) | (UInt16(bytes[2]) << 8))
            let modifiers = flags(for: bytes[3])
            guard bytes[4] <= 2 else {
                throw malformed("KEY action must be 0 (down), 1 (up), or 2 (tap); received \(bytes[4])")
            }
            return .key(code: keyCode, modifiers: modifiers, action: bytes[4])

        default:
            preconditionFailure("decode called for a non-keyboard frame")
        }
    }

    private static func execute(_ command: Command) throws {
        guard AXIsProcessTrusted() else {
            throw Failure(
                component: "KeyboardSynthesizer.execute",
                rootCause: "Pointer Mac is not trusted in Accessibility settings",
                failureType: "permissionDenied"
            )
        }

        switch command {
        case .text(let text):
            try post(text: text)
        case .key(let code, let modifiers, let action):
            switch action {
            case 0:
                try postKey(code: code, flags: modifiers, isDown: true)
            case 1:
                try postKey(code: code, flags: modifiers, isDown: false)
            case 2:
                try postKey(code: code, flags: modifiers, isDown: true)
                usleep(8_000)
                try postKey(code: code, flags: modifiers, isDown: false)
            default:
                preconditionFailure("KEY action was validated during decoding")
            }
        }
    }

    private static func post(text: String) throws {
        let utf16 = Array(text.utf16)
        var start = 0
        while start < utf16.count {
            var end = min(start + 20, utf16.count)
            if end < utf16.count, (0xD800...0xDBFF).contains(utf16[end - 1]) {
                end -= 1
            }
            let chunk = Array(utf16[start..<end])
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else {
                throw eventCreationFailure("CoreGraphics could not create a Unicode keyboard event")
            }
            chunk.withUnsafeBufferPointer { buffer in
                event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
            }
            event.post(tap: .cghidEventTap)
            start = end
        }
    }

    private static func postKey(code: CGKeyCode, flags: CGEventFlags, isDown: Bool) throws {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: isDown) else {
            throw eventCreationFailure("CoreGraphics could not create a key \(isDown ? "down" : "up") event")
        }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    private static func flags(for modifiers: UInt8) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers & 0x01 != 0 { flags.insert(.maskShift) }
        if modifiers & 0x02 != 0 { flags.insert(.maskControl) }
        if modifiers & 0x04 != 0 { flags.insert(.maskAlternate) }
        if modifiers & 0x08 != 0 { flags.insert(.maskCommand) }
        return flags
    }

    private static func malformed(_ rootCause: String) -> Failure {
        Failure(
            component: "KeyboardSynthesizer.decode",
            rootCause: rootCause,
            failureType: "malformedFrame"
        )
    }

    private static func eventCreationFailure(_ rootCause: String) -> Failure {
        Failure(
            component: "KeyboardSynthesizer.execute",
            rootCause: rootCause,
            failureType: "eventCreationFailed"
        )
    }
}
