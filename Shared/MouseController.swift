//
//  MouseController.swift
//  Shared
//

import Combine
import CoreGraphics
import Foundation

#if os(macOS)
import ApplicationServices
import AppKit
#endif

/// Maps watch attitude to cursor (macOS) + left-click events.
/// Pointing: **yaw → horizontal**, **roll → vertical** (absolute from origin pose).
final class MouseController: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var lastDeltaX: Double = 0
    @Published var lastDeltaY: Double = 0
    /// Higher default — small wrist angles should move the cursor a lot.
    @Published var sensitivity: Double = 1800
    @Published var precisionMode: Bool = false
    @Published var lastClickAt: Date?
    @Published var lastFailure: PointerFailurePayload?
    /// Absolute from origin pose (finger-point style) vs relative deltas.
    @Published var absolutePointing: Bool = true

    private var originRoll: Double?
    private var originYaw: Double?
    private var lastRoll: Double?
    private var lastYaw: Double?

    /// Entry from TCP / WCSession JSON (motion or control events).
    @discardableResult
    func processMessage(_ data: [String: Any]) -> PointerFailurePayload? {
        var didHandleClick = false
        if let type = data["type"] as? String {
            switch type {
            case "click":
                if let failure = leftClick() {
                    return failure
                }
                didHandleClick = true
                // Fall through if IMU keys also present (piggyback click).
            case "reset":
                resetDeltas()
                return nil
            case "wake":
                return nil
            default:
                break
            }
        }
        if !didHandleClick, (data["click"] as? NSNumber)?.boolValue == true {
            if let failure = leftClick() {
                return failure
            }
        }
        // Motion only if payload parses as IMU.
        if let payload = MotionPayload.fromDictionary(data) {
            return processMotion(payload)
        }
        return nil
    }

    @discardableResult
    func processMotion(_ data: [String: Any]) -> PointerFailurePayload? {
        guard let payload = MotionPayload.fromDictionary(data) else {
            return recordFailure(
                component: "MouseController.processMotion",
                rootCause: "Incoming dictionary did not include a complete IMU payload",
                failureType: .invalidPayload
            )
        }
        return processMotion(payload)
    }

    @discardableResult
    func processMotion(_ payload: MotionPayload) -> PointerFailurePayload? {
        let roll = payload.roll
        let yaw = payload.yaw
        let sens = precisionMode ? sensitivity / 10 : sensitivity

        if absolutePointing {
            if originRoll == nil || originYaw == nil {
                originRoll = roll
                originYaw = yaw
                lastRoll = roll
                lastYaw = yaw
                return nil
            }
            // Pointing: yaw left/right, roll up/down from rest pose.
            let dx = (yaw - originYaw!) * sens
            // Invert roll so "tilt hand up" moves cursor up on screen.
            let dy = -(roll - originRoll!) * sens
            lastDeltaX = dx
            lastDeltaY = dy
            if let failure = setCursorOffsetFromCenter(dx: dx, dy: dy) {
                return failure
            }
        } else {
            if let lastRoll, let lastYaw {
                let deltaX = (yaw - lastYaw) * sens
                let deltaY = -(roll - lastRoll) * sens
                lastDeltaX = deltaX
                lastDeltaY = deltaY
                if let failure = moveCursor(dx: deltaX, dy: deltaY) {
                    return failure
                }
            }
        }

        lastRoll = roll
        lastYaw = yaw
        lastFailure = nil
        return nil
    }

    /// Synthetic left-click at current cursor position (Accessibility required).
    @discardableResult
    func leftClick() -> PointerFailurePayload? {
        lastClickAt = Date()
        #if os(macOS)
        guard AXIsProcessTrusted() else {
            return recordFailure(
                component: "MouseController.leftClick",
                rootCause: "The Mac app is not trusted in Accessibility settings",
                failureType: .permissionDenied
            )
        }
        guard let currentEvent = CGEvent(source: nil) else {
            return recordFailure(
                component: "MouseController.leftClick",
                rootCause: "CoreGraphics could not read the current cursor location",
                failureType: .unavailableResource
            )
        }
        let point = currentEvent.location

        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let down = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseDown,
                mouseCursorPosition: point,
                mouseButton: .left
            ),
            let up = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseUp,
                mouseCursorPosition: point,
                mouseButton: .left
            )
        else {
            return recordFailure(
                component: "MouseController.leftClick",
                rootCause: "CoreGraphics could not create left mouse down/up events",
                failureType: .eventCreationFailed
            )
        }

        down.post(tap: .cghidEventTap)
        // Tiny delay makes some apps register the click more reliably.
        usleep(8_000)
        up.post(tap: .cghidEventTap)
        lastFailure = nil
        return nil
        #else
        return recordFailure(
            component: "MouseController.leftClick",
            rootCause: "Synthetic mouse clicks are only available in the Mac companion",
            failureType: .unsupportedPlatform
        )
        #endif
    }

    /// Absolute: center of main screen + offsets (pointing pose).
    @discardableResult
    private func setCursorOffsetFromCenter(dx: Double, dy: Double) -> PointerFailurePayload? {
        #if os(macOS)
        let frame = CGDisplayBounds(CGMainDisplayID())
        var point = CGPoint(
            x: frame.midX + dx,
            y: frame.midY + dy
        )
        point.x = max(frame.minX, min(frame.maxX - 1, point.x))
        point.y = max(frame.minY, min(frame.maxY - 1, point.y))
        return postMouseMove(to: point)
        #else
        _ = (dx, dy)
        return recordFailure(
            component: "MouseController.setCursorOffsetFromCenter",
            rootCause: "Cursor movement is only available in the Mac companion",
            failureType: .unsupportedPlatform
        )
        #endif
    }

    @discardableResult
    private func moveCursor(dx: Double, dy: Double) -> PointerFailurePayload? {
        #if os(macOS)
        guard let currentEvent = CGEvent(source: nil) else {
            return recordFailure(
                component: "MouseController.moveCursor",
                rootCause: "CoreGraphics could not read the current cursor location",
                failureType: .unavailableResource
            )
        }
        let frame = CGDisplayBounds(CGMainDisplayID())
        let current = currentEvent.location
        var newPoint = CGPoint(x: current.x + dx, y: current.y + dy)
        newPoint.x = max(frame.minX, min(frame.maxX - 1, newPoint.x))
        newPoint.y = max(frame.minY, min(frame.maxY - 1, newPoint.y))
        return postMouseMove(to: newPoint)
        #else
        _ = (dx, dy)
        return recordFailure(
            component: "MouseController.moveCursor",
            rootCause: "Cursor movement is only available in the Mac companion",
            failureType: .unsupportedPlatform
        )
        #endif
    }

    @discardableResult
    private func postMouseMove(to point: CGPoint) -> PointerFailurePayload? {
        #if os(macOS)
        guard AXIsProcessTrusted() else {
            return recordFailure(
                component: "MouseController.postMouseMove",
                rootCause: "The Mac app is not trusted in Accessibility settings",
                failureType: .permissionDenied
            )
        }
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            return recordFailure(
                component: "MouseController.postMouseMove",
                rootCause: "CoreGraphics could not create a mouse moved event",
                failureType: .eventCreationFailed
            )
        }
        CGWarpMouseCursorPosition(point)
        event.post(tap: .cghidEventTap)
        lastFailure = nil
        return nil
        #else
        return recordFailure(
            component: "MouseController.postMouseMove",
            rootCause: "Cursor movement is only available in the Mac companion",
            failureType: .unsupportedPlatform
        )
        #endif
    }

    func resetDeltas() {
        originRoll = nil
        originYaw = nil
        lastRoll = nil
        lastYaw = nil
        lastDeltaX = 0
        lastDeltaY = 0
        lastFailure = nil
    }

    @discardableResult
    private func recordFailure(
        component: String,
        rootCause: String,
        failureType: PointerFailurePayload.FailureType
    ) -> PointerFailurePayload {
        let failure = PointerFailurePayload(
            component: component,
            rootCause: rootCause,
            failureType: failureType
        )
        lastFailure = failure
        return failure
    }
}
