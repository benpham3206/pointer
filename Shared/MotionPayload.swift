//
//  MotionPayload.swift
//  Shared
//

import Foundation

struct PointerFailurePayload: Equatable, Sendable, CustomStringConvertible {
    enum FailureType: String, Sendable {
        case activationFailure
        case eventCreationFailed
        case invalidPayload
        case networkFailure
        case permissionDenied
        case serializationFailed
        case transportUnavailable
        case unavailableResource
        case unsupportedPlatform
    }

    let component: String
    let rootCause: String
    let failureType: FailureType

    var description: String {
        "\(component) [\(failureType.rawValue)]: \(rootCause)"
    }

    var dictionary: [String: String] {
        [
            "component": component,
            "rootCause": rootCause,
            "failureType": failureType.rawValue,
        ]
    }
}

/// Watch → companion motion + optional barometer samples.
struct MotionPayload: Equatable, Sendable {
    var roll: Double
    var pitch: Double
    var yaw: Double
    var ax: Double
    var ay: Double
    var az: Double
    var gx: Double
    var gy: Double
    var gz: Double
    /// Relative altitude (m) from `CMAltimeter`, when available.
    var relativeAltitudeM: Double?
    /// Barometric pressure (kPa), when available.
    var pressureKPa: Double?

    static let imuKeys: [String] = [
        "roll", "pitch", "yaw",
        "ax", "ay", "az",
        "gx", "gy", "gz",
    ]

    func toDictionary() -> [String: Any] {
        var d: [String: Any] = [
            "roll": roll, "pitch": pitch, "yaw": yaw,
            "ax": ax, "ay": ay, "az": az,
            "gx": gx, "gy": gy, "gz": gz,
        ]
        if let relativeAltitudeM { d["relativeAltitudeM"] = relativeAltitudeM }
        if let pressureKPa { d["pressureKPa"] = pressureKPa }
        return d
    }

    static func fromDictionary(_ data: [String: Any]) -> MotionPayload? {
        guard let roll = doubleValue(data["roll"]),
              let pitch = doubleValue(data["pitch"]),
              let yaw = doubleValue(data["yaw"]),
              let ax = doubleValue(data["ax"]),
              let ay = doubleValue(data["ay"]),
              let az = doubleValue(data["az"]),
              let gx = doubleValue(data["gx"]),
              let gy = doubleValue(data["gy"]),
              let gz = doubleValue(data["gz"]) else {
            return nil
        }
        return MotionPayload(
            roll: roll, pitch: pitch, yaw: yaw,
            ax: ax, ay: ay, az: az,
            gx: gx, gy: gy, gz: gz,
            relativeAltitudeM: doubleValue(data["relativeAltitudeM"]),
            pressureKPa: doubleValue(data["pressureKPa"])
        )
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let n = value as? NSNumber { return n.doubleValue }
        if let f = value as? Float { return Double(f) }
        return nil
    }
}
