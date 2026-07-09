//
//  CursorAccessibility.swift
//  pointer
//

#if os(macOS)
import ApplicationServices
import Foundation

enum CursorAccessibility {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestTrustPrompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
#endif