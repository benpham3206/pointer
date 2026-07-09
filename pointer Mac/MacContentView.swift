//
//  MacContentView.swift
//  pointer Mac
//

import SwiftUI

struct MacContentView: View {
    @EnvironmentObject private var mouseController: MouseController
    @EnvironmentObject private var motionReceiver: MacMotionReceiver

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            connectionSection
            if mouseController.isConnected {
                motionSection
            }
            sensitivitySection
            accessibilitySection
            if let error = motionReceiver.lastReceiveError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let failure = mouseController.lastFailure {
                Text(failure.description)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(24)
        .frame(minWidth: 380, minHeight: 420)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "cursorarrow.rays")
                .font(.largeTitle)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text("Pointer Mac")
                    .font(.title2.bold())
                Text("Receives motion from iPhone over local network")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var connectionSection: some View {
        GroupBox("Network") {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    motionReceiver.isListening ? "Bonjour listener active" : "Listener stopped",
                    systemImage: motionReceiver.isListening ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash"
                )
                .foregroundStyle(motionReceiver.isListening ? .green : .orange)

                Text(motionReceiver.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Clients")
                    Spacer()
                    Text("\(motionReceiver.activeConnections)")
                        .monospacedDigit()
                }
                if let control = motionReceiver.lastControlMessage {
                    HStack {
                        Text("Last control")
                        Spacer()
                        Text(control)
                            .monospaced()
                    }
                    .font(.caption)
                }

                Label(
                    mouseController.isConnected ? "Receiving motion" : "No active client",
                    systemImage: mouseController.isConnected ? "iphone.radiowaves.left.and.right" : "iphone.slash"
                )
                .foregroundStyle(mouseController.isConnected ? .green : .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var motionSection: some View {
        GroupBox("Last delta") {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(format: "ΔX: %.3f", mouseController.lastDeltaX))
                Text(String(format: "ΔY: %.3f", mouseController.lastDeltaY))
            }
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sensitivitySection: some View {
        GroupBox("Control") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Sensitivity")
                    Spacer()
                    Text("\(Int(mouseController.sensitivity))")
                        .monospacedDigit()
                }
                Slider(value: $mouseController.sensitivity, in: 100...2000, step: 50)
                Toggle("Precision mode (÷10)", isOn: $mouseController.precisionMode)
            }
        }
    }

    private var accessibilitySection: some View {
        GroupBox("Accessibility") {
            VStack(alignment: .leading, spacing: 10) {
                if CursorAccessibility.isTrusted {
                    Label("Accessibility granted — cursor control enabled", systemImage: "checkmark.shield")
                        .foregroundStyle(.green)
                } else {
                    Label("Accessibility required to move the cursor", systemImage: "exclamationmark.shield")
                        .foregroundStyle(.orange)
                    Text("Grant Pointer in System Settings → Privacy & Security → Accessibility.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Accessibility Settings") {
                        CursorAccessibility.requestTrustPrompt()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        Text("Service: \(MacMotionReceiver.serviceName) · \(MacMotionReceiver.bonjourType) · companion bundle bp.pointer")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

#Preview {
    let mouse = MouseController()
    return MacContentView()
        .environmentObject(mouse)
        .environmentObject(MacMotionReceiver(mouseController: mouse))
}
