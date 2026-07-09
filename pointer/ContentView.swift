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
                HStack {
                    Image(systemName: phoneWatchReceiver.isWatchConnected ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
                        .imageScale(.large)
                        .foregroundStyle(phoneWatchReceiver.isWatchConnected ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(phoneWatchReceiver.statusSummary)
                            .font(.headline)
                        Text("Mac: \(macForwarderTitle(for: phoneWatchReceiver.macForwarder.status)) · msgs \(phoneWatchReceiver.messagesReceived)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

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
                watchLinkStatusView()

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

    private func sensorLine(_ name: String, _ value: Double) -> some View {
        Text(String(format: "%@ %+9.4f", name, value))
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
