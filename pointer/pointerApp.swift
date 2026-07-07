//
//  pointerApp.swift
//  pointer
//

import SwiftUI
import WatchConnectivity
import Combine
import CoreGraphics

#if os(macOS)
import AppKit
#endif

@main
struct pointerApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(macOS)
                .environmentObject(appDelegate.mouseController)
                #endif
        }
    }
}

// Make MouseController available on all platforms. The cursor-moving logic is macOS-only.
final class MouseController: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var lastDeltaX: Double = 0
    @Published var lastDeltaY: Double = 0
    @Published var sensitivity: Double = 600
    @Published var precisionMode: Bool = false
    
    private var lastRoll: Double?
    private var lastPitch: Double?
    
    func processMotion(_ data: [String: Any]) {
        guard let roll = data["roll"] as? Double,
              let pitch = data["pitch"] as? Double else { return }
        
        if let lastRoll, let lastPitch {
            let effectiveSensitivity = precisionMode ? sensitivity / 10 : sensitivity
            let deltaX = (roll - lastRoll) * effectiveSensitivity
            let deltaY = (pitch - lastPitch) * effectiveSensitivity
            
            self.lastDeltaX = deltaX
            self.lastDeltaY = deltaY
            
            moveCursor(dx: deltaX, dy: deltaY)
        }
        
        self.lastRoll = roll
        self.lastPitch = pitch
    }
    
    private func moveCursor(dx: Double, dy: Double) {
        #if os(macOS)
        guard let screen = NSScreen.main else { return }
        
        let current = NSEvent.mouseLocation
        let frame = screen.frame
        
        // CoreGraphics uses bottom-left origin; NSEvent.mouseLocation uses flipped Y
        let cgY = frame.height - current.y
        
        var newPoint = CGPoint(
            x: current.x + dx,
            y: cgY + dy
        )
        
        // Clamp to screen bounds
        newPoint.x = max(0, min(frame.width, newPoint.x))
        newPoint.y = max(0, min(frame.height, newPoint.y))
        
        CGWarpMouseCursorPosition(newPoint)
        #else
        // Non-macOS platforms: no-op
        _ = (dx, dy)
        #endif
    }
    
    func resetDeltas() {
        lastRoll = nil
        lastPitch = nil
    }
}

#if os(macOS)
final class AppDelegate: NSObject, NSApplicationDelegate, WCSessionDelegate {
    let mouseController: MouseController = MouseController()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }
    
    // MARK: - WCSessionDelegate
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.mouseController.isConnected = (activationState == .activated)
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        DispatchQueue.main.async {
            self.mouseController.isConnected = false
        }
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        DispatchQueue.main.async {
            self.mouseController.isConnected = false
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        DispatchQueue.main.async {
            self.mouseController.processMotion(message)
        }
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.mouseController.isConnected = session.isReachable
        }
    }
}
#endif
