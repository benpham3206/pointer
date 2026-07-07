//
//  MotionManager.swift
//  pointer Watch App
//

import Foundation
import CoreMotion
import WatchConnectivity
import Combine

class MotionManager: NSObject, ObservableObject, WCSessionDelegate {
    private let motion = CMMotionManager()
    let session = WCSession.default
    
    @Published var isTracking = false
    @Published var lastRoll: Double = 0
    @Published var lastPitch: Double = 0
    @Published var lastYaw: Double = 0
    
    override init() {
        super.init()
        session.delegate = self
        session.activate()
    }
    
    func toggleTracking() {
        isTracking ? stopTracking() : startTracking()
    }
    
    func startTracking() {
        guard motion.isDeviceMotionAvailable else { return }
        guard session.activationState == .activated else { return }
        
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, error in
            guard let self = self, let data = data else { return }
            
            self.lastRoll = data.attitude.roll
            self.lastPitch = data.attitude.pitch
            self.lastYaw = data.attitude.yaw
            
            let payload: [String: Any] = [
                "roll": data.attitude.roll,
                "pitch": data.attitude.pitch,
                "yaw": data.attitude.yaw,
                "ax": data.userAcceleration.x,
                "ay": data.userAcceleration.y,
                "az": data.userAcceleration.z,
                "gx": data.rotationRate.x,
                "gy": data.rotationRate.y,
                "gz": data.rotationRate.z
            ]
            
            if self.session.isReachable {
                self.session.sendMessage(payload, replyHandler: nil) { error in
                    print("WCSession send error: \(error.localizedDescription)")
                }
            }
        }
        
        isTracking = true
    }
    
    func stopTracking() {
        motion.stopDeviceMotionUpdates()
        isTracking = false
    }
    
    // MARK: - WCSessionDelegate
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("WCSession activation error: \(error.localizedDescription)")
        }
    }
}

