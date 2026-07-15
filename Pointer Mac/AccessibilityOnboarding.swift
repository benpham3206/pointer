//
//  AccessibilityOnboarding.swift
//  Pointer Mac
//

import ApplicationServices
import Foundation

/// Accessibility trust is required for synthetic cursor moves and clicks.
enum AccessibilityOnboarding {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts once via System Settings if not already trusted.
    static func requestTrustPrompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}
