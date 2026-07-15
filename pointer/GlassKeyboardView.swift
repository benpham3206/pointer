//
//  GlassKeyboardView.swift
//  pointer (iOS)
//
//  Liquid-glass pop-up keyboard (visionOS feel). Self-contained: emits key/text
//  events through closures; the host wires them to MacForwarder.sendText/sendKey.
//

#if os(iOS)
import SwiftUI

/// macOS virtual keycodes for special keys (kVK_*), matching the 0x07 frame contract.
enum MacKey {
    static let `return`: Int = 0x24
    static let delete: Int = 0x33
    static let space: Int = 0x31
    static let escape: Int = 0x35
    static let tab: Int = 0x30
}

struct GlassKeyboardView: View {
    /// Send literal text (typed characters) to the Mac.
    var sendText: (String) -> Void
    /// Send a special key tap: (keycode, modifiers) — modifiers bit0 shift…bit3 cmd.
    var sendKey: (Int, Int) -> Void

    @State private var shifted = false
    @State private var symbols = false
    @State private var backspaceTimer: Timer?
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    private static let letterRows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    private static let symbolRows = ["1234567890", "-/:;()$&@\"", ".,?!'#%^*+="]

    private var rows: [[String]] {
        let source = symbols ? Self.symbolRows : Self.letterRows
        return source.map { $0.map { c in
            let s = String(c)
            return shifted && !symbols ? s.uppercased() : s
        } }
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 5) {
                    if r == 2 { modifierKey(symbols ? "#+=" : (shifted ? "⇧" : "⇧").description) }
                    ForEach(rows[r], id: \.self) { key in
                        charKey(key)
                    }
                    if r == 2 { backspaceKey }
                }
            }
            bottomRow
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .onAppear { haptic.prepare() }
        .onDisappear { stopBackspaceRepeat() }
    }

    // MARK: keys

    private func charKey(_ key: String) -> some View {
        Button {
            haptic.impactOccurred()
            sendText(key)
            if shifted && !symbols { shifted = false }
        } label: {
            Text(key)
                .font(.system(size: 20, weight: .regular, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 42)
        }
        .buttonStyle(.plain)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func modifierKey(_ label: String) -> some View {
        Button {
            haptic.impactOccurred()
            if symbols { symbols = false } else { shifted.toggle() }
        } label: {
            Text(label)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 44, height: 42)
        }
        .buttonStyle(.plain)
        .background(shifted && !symbols ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.thinMaterial),
                    in: RoundedRectangle(cornerRadius: 8))
    }

    private var backspaceKey: some View {
        Button {
            haptic.impactOccurred()
            sendKey(MacKey.delete, 0)
        } label: {
            Image(systemName: "delete.left")
                .frame(width: 44, height: 42)
        }
        .buttonStyle(.plain)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in startBackspaceRepeat() }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0).onEnded { _ in stopBackspaceRepeat() }
        )
    }

    private var bottomRow: some View {
        HStack(spacing: 5) {
            Button(symbols ? "ABC" : "123") {
                haptic.impactOccurred()
                symbols.toggle()
            }
            .font(.system(size: 15, weight: .medium))
            .frame(width: 52, height: 42)
            .buttonStyle(.plain)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))

            Button {
                haptic.impactOccurred()
                sendText(" ")
            } label: {
                Text("space")
                    .font(.system(size: 15))
                    .frame(maxWidth: .infinity, minHeight: 42)
            }
            .buttonStyle(.plain)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))

            Button {
                haptic.impactOccurred()
                sendKey(MacKey.return, 0)
            } label: {
                Text("return")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 76, height: 42)
            }
            .buttonStyle(.plain)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: backspace repeat (sender-side, ~12 Hz after 400 ms hold)

    private func startBackspaceRepeat() {
        stopBackspaceRepeat()
        backspaceTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12.0, repeats: true) { _ in
            sendKey(MacKey.delete, 0)
        }
    }

    private func stopBackspaceRepeat() {
        backspaceTimer?.invalidate()
        backspaceTimer = nil
    }
}

#Preview {
    GlassKeyboardView(sendText: { _ in }, sendKey: { _, _ in })
        .padding()
}
#endif
