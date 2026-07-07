//
//  ContentView.swift
//  pointer Watch App
//

import SwiftUI

struct ContentView: View {
    @StateObject private var motionManager = MotionManager()
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: motionManager.isTracking ? "cursorarrow.motionlines" : "cursorarrow")
                .imageScale(.large)
                .foregroundStyle(motionManager.isTracking ? .green : .secondary)
            
            Text(motionManager.isTracking ? "Tracking" : "Idle")
                .font(.headline)
            
            if motionManager.isTracking {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: "R: %.2f", motionManager.lastRoll))
                        .font(.caption2.monospaced())
                    Text(String(format: "P: %.2f", motionManager.lastPitch))
                        .font(.caption2.monospaced())
                    Text(String(format: "Y: %.2f", motionManager.lastYaw))
                        .font(.caption2.monospaced())
                }
                .foregroundStyle(.secondary)
            }
            
            Button(action: { motionManager.toggleTracking() }) {
                Text(motionManager.isTracking ? "Stop" : "Start")
                    .fontWeight(.semibold)
            }
            .tint(motionManager.isTracking ? .red : .green)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
