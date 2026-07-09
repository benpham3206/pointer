//
//  CursorAccessibility.swift
//  pointer Mac
//

import ApplicationServices
import Foundation

/// Accessibility trust is required for `CGWarpMouseCursorPosition` / synthetic pointer events.
enum CursorAccessibility {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user once (if not already trusted) via System Settings.
    static func requestTrustPrompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}