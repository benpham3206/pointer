//
//  ContentView.swift
//  pointer
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var mouseController: MouseController
    
    var body: some View {
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
}

#Preview {
    ContentView()
        .environmentObject(MouseController())
}
