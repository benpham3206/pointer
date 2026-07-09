//
//  pointerApp.swift
//  pointer
//

import SwiftUI

#if os(iOS)
import WatchConnectivity
#endif

#if os(macOS)
import AppKit
#endif

@main
struct pointerApp: App {
    #if os(iOS)
    @StateObject private var phoneWatchReceiver = PhoneWatchReceiver()
    #endif
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            rootContent
        }
        #if os(macOS)
        .defaultSize(width: 420, height: 480)
        #endif
    }

    @ViewBuilder
    private var rootContent: some View {
        #if os(iOS)
        ContentView()
            .environmentObject(phoneWatchReceiver)
            .onAppear {
                phoneWatchReceiver.activateSessionIfNeeded()
            }
        #elseif os(macOS)
        MacContentView()
            .environmentObject(appDelegate.mouseController)
            .environmentObject(appDelegate.motionReceiver)
        #endif
    }
}

#if os(macOS)
/// macOS: Bonjour TCP listener → `MouseController` (CGEventPost). iOS relays Watch motion via `MacForwarder`.
final class AppDelegate: NSObject, NSApplicationDelegate {
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
#endif