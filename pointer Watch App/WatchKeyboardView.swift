//
//  WatchKeyboardView.swift
//  pointer Watch App
//
//  Compact Mac keyboard: dictation/scribble text entry + a strip of special keys.
//  visionOS-style: translucent materials, immediate haptic per send.
//

import SwiftUI
import WatchKit

struct WatchKeyboardView: View {
    @ObservedObject var motionManager: MotionManager
    @State private var draft = ""

    private struct Special: Identifiable {
        let id: String
        let symbol: String
        let keycode: Int
    }

    // macOS kVK codes (match the 0x07 frame contract).
    private let specials: [Special] = [
        .init(id: "space", symbol: "space", keycode: 0x31),
        .init(id: "return", symbol: "return", keycode: 0x24),
        .init(id: "delete", symbol: "delete.left", keycode: 0x33),
        .init(id: "esc", symbol: "escape", keycode: 0x35),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                TextField("Dictate or scribble…", text: $draft)
                    .onSubmit(sendDraft)

                Button {
                    sendDraft()
                } label: {
                    Label("Send to Mac", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(.blue)
                .disabled(draft.isEmpty)

                HStack(spacing: 6) {
                    ForEach(specials) { key in
                        Button {
                            WKInterfaceDevice.current().play(.click)
                            motionManager.sendKey(keycode: key.keycode)
                        } label: {
                            Image(systemName: key.symbol == "space" ? "space" : key.symbol)
                                .frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .buttonStyle(.glass)
                    }
                }
                Text("Keys go straight to the Mac cursor's focus.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Mac Keyboard")
    }

    private func sendDraft() {
        guard !draft.isEmpty else { return }
        WKInterfaceDevice.current().play(.click)
        motionManager.sendText(draft)
        draft = ""
    }
}
