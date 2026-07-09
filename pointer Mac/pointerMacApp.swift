//
//  pointerMacApp.swift
//  pointer Mac
//

import SwiftUI
import AppKit

@main
struct PointerMacApp: App {
    @NSApplicationDelegateAdaptor(PointerMacAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            MacContentView()
                .environmentObject(appDelegate.mouseController)
                .environmentObject(appDelegate.motionReceiver)
        }
        .defaultSize(width: 420, height: 480)
    }
}

final class PointerMacAppDelegate: NSObject, NSApplicationDelegate {
    let mouseController = MouseController()
    lazy var motionReceiver = MacMotionReceiver(mouseController: mouseController)

    func applicationDidFinishLaunching(_ notification: Notification) {
        CursorAccessibility.requestTrustPrompt()
        motionReceiver.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        motionReceiver.stop()
    }
}