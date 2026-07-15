//
//  ContentView.swift
//  pointer
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct ContentView: View {
    #if os(iOS)
    @EnvironmentObject var phoneWatchReceiver: PhoneWatchReceiver
    @AppStorage("sensorDebugHost") private var sensorDebugHost: String = ""
    @AppStorage("sensorDebugEnabled") private var sensorDebugEnabled: Bool = false
    @State private var phonePointerOn = false
    @State private var phoneEngine: PhonePointerEngine?
    @State private var showKeyboard = false
    @State private var phoneCalibNote: String?
    @State private var phoneCalibExpanded = false
    #elseif os(macOS)
    @EnvironmentObject var mouseController: MouseController
    #endif

    var body: some View {
        #if os(iOS)
        iosBody
        #elseif os(macOS)
        macBody
        #else
        Text("Unsupported platform")
        #endif
    }

    #if os(iOS)
    private var iosBody: some View {
        let forwarder = phoneWatchReceiver.macForwarder

        return ScrollView {
            VStack(spacing: 16) {
                statusCluster

                if let p = phoneWatchReceiver.lastPayload {
                    GroupBox("Live IMU (last sample)") {
                        VStack(alignment: .leading, spacing: 4) {
                            sensorLine("roll", p.roll); sensorLine("pitch", p.pitch); sensorLine("yaw", p.yaw)
                            Divider()
                            sensorLine("ax", p.ax); sensorLine("ay", p.ay); sensorLine("az", p.az)
                            Divider()
                            sensorLine("gx", p.gx); sensorLine("gy", p.gy); sensorLine("gz", p.gz)
                            if let alt = p.relativeAltitudeM, let kpa = p.pressureKPa {
                                Divider()
                                sensorLine("rel alt m", alt); sensorLine("pressure kPa", kpa)
                            }
                        }
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                macForwarderStatusView(forwarder: forwarder)

                GroupBox("iPhone pointer") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                forwarder.forwardMotion(["type": "click"])
                            } label: {
                                Label("Click", systemImage: "cursorarrow.click")
                                    .frame(maxWidth: .infinity, minHeight: 36)
                            }
                            .buttonStyle(.glassProminent)

                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                forwarder.forwardMotion(["type": "click", "button": "right"])
                            } label: {
                                Label("Right click", systemImage: "cursorarrow.click.2")
                                    .frame(maxWidth: .infinity, minHeight: 36)
                            }
                            .buttonStyle(.glass)
                        }

                        Toggle("Use iPhone as pointer", isOn: $phonePointerOn)
                            .onChange(of: phonePointerOn) { _, on in
                                if !on { setPhoneCalibrationExpanded(false) }
                                setPhonePointer(on)
                            }
                        Text(phonePointerOn
                             ? "Wand grip: top speaker (+Y) points at the screen. Watch cursor is paused."
                             : "Watch controls the cursor.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if phonePointerOn {
                            // Live ray angles: azimuth should INCREASE pointing right,
                            // elevation should INCREASE pointing up.
                            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                                if let a = phoneEngine?.currentFilteredAttitude() {
                                    Text(String(format: "azimuth %+.2f rad · elevation %+.2f rad", a.yaw, a.roll))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("azimuth — · elevation — (settling…)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        if let failure = phoneEngine?.lastFailure?["rootCause"], phonePointerOn {
                            Text(failure)
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                        Button {
                            showKeyboard.toggle()
                        } label: {
                            Label(showKeyboard ? "Hide Mac keyboard" : "Type on Mac", systemImage: "keyboard")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)

                        if phonePointerOn {
                            DisclosureGroup(
                                "Calibrate corners",
                                isExpanded: Binding(
                                    get: { phoneCalibExpanded },
                                    set: { setPhoneCalibrationExpanded($0) }
                                )
                            ) {
                                PhoneCalibrationView(
                                    captureAttitude: { phoneEngine?.currentFilteredAttitude() },
                                    sendCorner: { name, pose in
                                        forwarder.forwardMotion([
                                            "type": "calib", "corner": name,
                                            "roll": pose.roll, "yaw": pose.yaw, "pitch": pose.pitch,
                                        ])
                                    },
                                    onFinished: { note in
                                        phoneCalibNote = note
                                        setPhoneCalibrationExpanded(false)
                                    }
                                )
                            }
                            .font(.subheadline)
                            if let note = phoneCalibNote {
                                Text(note)
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }

                if showKeyboard {
                    GlassKeyboardView(
                        sendText: { forwarder.sendText($0) },
                        sendKey: { keycode, modifiers in
                            forwarder.sendKey(keycode: keycode, modifiers: modifiers, action: 2)
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if !forwarder.discoveredMacs.isEmpty {
                    Picker("Mac", selection: Binding(
                        get: { forwarder.selectedMacID ?? forwarder.discoveredMacs.first?.id ?? "" },
                        set: { forwarder.selectMac(id: $0) }
                    )) {
                        ForEach(forwarder.discoveredMacs) { mac in
                            Text(mac.name).tag(mac.id)
                        }
                    }
                    .pickerStyle(.menu)
                }

                DisclosureGroup("Diagnostics") {
                    VStack(alignment: .leading, spacing: 12) {
                        watchLinkStatusView()
                        GroupBox("Python tracker (Mac)") {
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle("Stream to Mac TCP :19778", isOn: $sensorDebugEnabled)
                                    .onChange(of: sensorDebugEnabled) { _, _ in applyDebugStream() }
                                TextField("Mac LAN IP", text: $sensorDebugHost)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .onChange(of: sensorDebugHost) { _, _ in applyDebugStream() }
                                Text("Run `python3 tools/watch_sensor_tracker.py` on your Mac, then enter this Mac’s IP.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .font(.subheadline)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Messages: \(phoneWatchReceiver.messagesReceived)")
                    Text("Forwarded: \(forwarder.packetsForwarded)")
                        .font(.system(.caption, design: .monospaced))
                    if forwarder.packetsQueued > 0 {
                        Text("Queued for Mac: \(forwarder.packetsQueued)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.orange)
                    }
                    if let control = phoneWatchReceiver.lastControlMessage {
                        Text("Last control: \(control)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if phoneWatchReceiver.isBackgroundRelayActive {
                        Text("Background relay active")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                    if let at = phoneWatchReceiver.lastMessageAt {
                        Text("Last: \(at.formatted(date: .omitted, time: .standard))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.secondary)

                Text("Watch: Sensor tracker UI. iPhone: mirror + optional Python. Xcode console also logs WCSession errors.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let error = phoneWatchReceiver.lastErrorDescription {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                if let watchError = phoneWatchReceiver.lastWatchError {
                    Text("⌚️ Watch: \(watchError)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
        }
        .onAppear {
            applyDebugStream()
            phoneWatchReceiver.activateSessionIfNeeded()
            phoneWatchReceiver.macForwarder.ensureConnected()
            #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = true
            #endif
        }
        .onDisappear {
            #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = false
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            phoneWatchReceiver.activateSessionIfNeeded()
            phoneWatchReceiver.macForwarder.ensureConnected()
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            phoneWatchReceiver.macForwarder.ensureConnected()
        }
    }

    /// visionOS-style status cluster: translucent capsules, honest state only.
    private var statusCluster: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                statusCapsule(
                    icon: phoneWatchReceiver.isWatchConnected ? "applewatch.radiowaves.left.and.right" : "applewatch.slash",
                    label: phoneWatchReceiver.isWatchConnected ? "Watch" : "No watch",
                    ok: phoneWatchReceiver.isWatchConnected
                )
                statusCapsule(
                    icon: "desktopcomputer",
                    label: macCapsuleLabel,
                    ok: isMacConnected
                )
                statusCapsule(
                    icon: phonePointerOn ? "iphone.gen3" : "hand.point.up.left",
                    label: phonePointerOn ? "iPhone pointer" : "Watch pointer",
                    ok: true
                )
            }
            Text(phoneWatchReceiver.statusSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var isMacConnected: Bool {
        if case .connected = phoneWatchReceiver.macForwarder.status { return true }
        return false
    }

    private var macCapsuleLabel: String {
        if case .connected(let host) = phoneWatchReceiver.macForwarder.status { return host }
        return "Searching…"
    }

    private func statusCapsule(icon: String, label: String, ok: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .imageScale(.small)
            Text(label)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(ok ? Color.green.opacity(0.35) : Color.orange.opacity(0.45)))
    }

    private func sensorLine(_ name: String, _ value: Double) -> some View {
        Text(String(format: "%@ %+9.4f", name, value))
    }

    private func setPhonePointer(_ on: Bool) {
        let forwarder = phoneWatchReceiver.macForwarder
        if on {
            if phoneEngine == nil {
                phoneEngine = PhonePointerEngine { frame in
                    forwarder.forwardMotion(frame)
                }
            }
            forwarder.phonePointerEngaged = true
            phoneEngine?.start()
        } else {
            phoneEngine?.stop()
            forwarder.phonePointerEngaged = false
        }
    }

    private func setPhoneCalibrationExpanded(_ expanded: Bool) {
        phoneCalibExpanded = expanded
        phoneEngine?.isCalibrating = expanded
    }

    private func applyDebugStream() {
        phoneWatchReceiver.updateDebugStream(
            host: sensorDebugHost,
            port: SensorDebugStreamer.defaultPort,
            enabled: sensorDebugEnabled
        )
    }

    private var watchStatusLabel: String {
        if phoneWatchReceiver.isSessionActivated {
            return phoneWatchReceiver.isWatchReachable ? "Watch Connected" : "Watch Paired (not reachable)"
        }
        return "Watch Disconnected"
    }

    @ViewBuilder
    private func macForwarderStatusView(forwarder: MacForwarder) -> some View {
        HStack(spacing: 10) {
            Image(systemName: macForwarderIcon(for: forwarder.status))
                .foregroundStyle(macForwarderColor(for: forwarder.status))
            VStack(alignment: .leading, spacing: 4) {
                Text(macForwarderTitle(for: forwarder.status))
                    .font(.subheadline.weight(.semibold))
                if let err = forwarder.lastSendError {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func watchLinkStatusView() -> some View {
        GroupBox("Watch link") {
            VStack(alignment: .leading, spacing: 6) {
                linkFlag("Activated", phoneWatchReceiver.isSessionActivated)
                linkFlag("Paired", phoneWatchReceiver.isWatchPaired)
                linkFlag("Watch app", phoneWatchReceiver.isWatchAppInstalled)
                linkFlag("Reachable", phoneWatchReceiver.isWatchReachable)
            }
            .font(.caption.monospacedDigit())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func linkFlag(_ title: String, _ value: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value ? "yes" : "no")
                .foregroundStyle(value ? .green : .orange)
        }
    }

    private func macForwarderIcon(for status: MacForwarder.ConnectionStatus) -> String {
        switch status {
        case .connected: return "desktopcomputer.and.arrow.down"
        case .connecting, .browsing: return "antenna.radiowaves.left.and.right"
        case .failed: return "exclamationmark.triangle"
        default: return "desktopcomputer.trianglebadge.exclamationmark"
        }
    }

    private func macForwarderColor(for status: MacForwarder.ConnectionStatus) -> Color {
        switch status {
        case .connected: return .green
        case .connecting, .browsing: return .yellow
        case .failed: return .red
        default: return .secondary
        }
    }

    private func macForwarderTitle(for status: MacForwarder.ConnectionStatus) -> String {
        switch status {
        case .idle: return "Mac relay idle"
        case .browsing: return "Searching for Mac…"
        case .connecting: return "Connecting to Mac…"
        case .connected(let host): return "Forwarding to \(host)"
        case .disconnected: return "Mac relay disconnected"
        case .failed(let message): return "Mac relay failed: \(message)"
        }
    }
    #endif

    #if os(macOS)
    private var macBody: some View {
        VStack(spacing: 20) {
            HStack {
                Image(systemName: mouseController.isConnected ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
                    .imageScale(.large)
                    .foregroundStyle(mouseController.isConnected ? .green : .red)

                Text(mouseController.isConnected ? "Watch Connected" : "Watch Disconnected")
                    .font(.headline)
            }

            if mouseController.isConnected {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(format: "Delta X: %.2f", mouseController.lastDeltaX))
                        .font(.system(.body, design: .monospaced))
                    Text(String(format: "Delta Y: %.2f", mouseController.lastDeltaY))
                        .font(.system(.body, design: .monospaced))
                }
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Sensitivity")
                    Spacer()
                    Text("\(Int(mouseController.sensitivity))")
                        .monospacedDigit()
                }
                Slider(value: $mouseController.sensitivity, in: 100...2000, step: 50)

                Toggle("Precision Mode (1/10x)", isOn: $mouseController.precisionMode)
            }
            .padding(.horizontal)

            Spacer()

            Text("Start tracking on your Apple Watch to control the cursor")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(minWidth: 320, minHeight: 280)
    }
    #endif
}

#Preview {
    #if os(iOS)
    ContentView()
        .environmentObject(PhoneWatchReceiver())
    #elseif os(macOS)
    ContentView()
        .environmentObject(MouseController())
    #endif
}
