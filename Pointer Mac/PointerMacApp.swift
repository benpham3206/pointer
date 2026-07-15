//
//  PointerMacApp.swift
//  Pointer Mac
//

import SwiftUI

@main
struct PointerMacApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Image(systemName: "cursorarrow.rays")
        }
        .menuBarExtraStyle(.window)
    }
}
