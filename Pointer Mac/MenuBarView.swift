//
//  MenuBarView.swift
//  Pointer Mac
//
//  Status + controls for the menu-bar popover. Reads the AppState interface
//  contract fixed in the Sol-P1 brief; latency honesty per docs/DESIGN.md —
//  every row reflects reported state, never optimistic state.
//

import ServiceManagement
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            statusCluster
            calibrationSection
            controlSection
            onboardingSection
            footer
        }
        .padding(16)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "cursorarrow.rays")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Pointer")
                    .font(.headline)
                Text("Watch & iPhone → this Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusCluster: some View {
        VStack(alignment: .leading, spacing: 6) {
            statusRow(
                icon: "antenna.radiowaves.left.and.right",
                title: "Network",
                detail: appState.udpState,
                healthy: appState.udpState.hasPrefix("listening")
            )
            statusRow(
                icon: "wave.3.right",
                title: "Bluetooth",
                detail: appState.bleState,
                healthy: !appState.bleState.hasPrefix("off")
            )
            statusRow(
                icon: "speedometer",
                title: "Motion",
                detail: appState.framesPerSecond > 0
                    ? String(format: "%.0f frames/s", appState.framesPerSecond)
                    : "no frames",
                healthy: appState.framesPerSecond > 0
            )
            if let failure = appState.lastFailure {
                Text(failure)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
    }

    private var calibrationSection: some View {
        GroupBox {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(appState.isCalibrated ? "Calibrated" : "Not calibrated")
                        .font(.subheadline.weight(.medium))
                    Text(
                        appState.calibratedCorners.isEmpty
                            ? "Capture TL → TR → BL → BR from the Watch"
                            : appState.calibratedCorners.joined(separator: " · ").uppercased()
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear", role: .destructive) {
                    appState.clearCalibration()
                }
                .controlSize(.small)
                .disabled(appState.calibratedCorners.isEmpty)
            }
        }
    }

    private var controlSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                labeledSlider("Sensitivity", value: $appState.sensitivity, in: 0.1...2.0, format: "%.2f")
                labeledSlider("Dead zone", value: $appState.deadzone, in: 0...10, format: "%.0f px")
                labeledSlider("Edge boost", value: $appState.accel, in: 0...4, format: "%.1f×")
                Picker("Display", selection: $appState.displayMode) {
                    Text("External").tag("external")
                    Text("Main").tag("main")
                    Text("Largest").tag("largest")
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var onboardingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !AccessibilityOnboarding.isTrusted {
                Button {
                    AccessibilityOnboarding.requestTrustPrompt()
                } label: {
                    Label("Grant Accessibility (required)", systemImage: "exclamationmark.shield")
                }
                .foregroundStyle(.orange)
            }
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enable in
                    do {
                        if enable {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
        }
    }

    private var footer: some View {
        HStack {
            Text("bp.pointer.macos")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Quit Pointer") {
                NSApp.terminate(nil)
            }
            .controlSize(.small)
        }
    }

    private func statusRow(icon: String, title: String, detail: String, healthy: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(healthy ? .green : .orange)
            Text(title)
                .font(.callout)
            Spacer()
            Text(detail)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func labeledSlider(
        _ title: String,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        format: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.callout)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }
}
