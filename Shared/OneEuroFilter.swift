import Foundation

/// Timestamp-aware One-Euro smoothing for angles measured in radians.
struct OneEuroFilter {
    let minCutoff: Double
    let beta: Double
    let derivativeCutoff: Double

    private var previousTimestamp: TimeInterval?
    private var previousAngle = 0.0
    private var filteredAngle = 0.0
    private var filteredDerivative = 0.0

    init(minCutoff: Double, beta: Double, derivativeCutoff: Double) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }

    mutating func filter(_ angle: Double, timestamp: TimeInterval) -> Double {
        let angle = Self.wrapped(angle)
        guard let previousTimestamp else {
            self.previousTimestamp = timestamp
            previousAngle = angle
            filteredAngle = angle
            filteredDerivative = 0
            return angle
        }

        let elapsed = timestamp - previousTimestamp
        guard elapsed > 0 else { return filteredAngle }

        let derivative = Self.angularDifference(from: previousAngle, to: angle) / elapsed
        let derivativeAlpha = Self.alpha(cutoff: derivativeCutoff, elapsed: elapsed)
        filteredDerivative += derivativeAlpha * (derivative - filteredDerivative)

        let cutoff = minCutoff + beta * abs(filteredDerivative)
        let angleAlpha = Self.alpha(cutoff: cutoff, elapsed: elapsed)
        filteredAngle = Self.wrapped(
            filteredAngle + angleAlpha * Self.angularDifference(from: filteredAngle, to: angle)
        )

        self.previousTimestamp = timestamp
        previousAngle = angle
        return filteredAngle
    }

    mutating func reset() {
        previousTimestamp = nil
        previousAngle = 0
        filteredAngle = 0
        filteredDerivative = 0
    }

    private static func alpha(cutoff: Double, elapsed: TimeInterval) -> Double {
        let timeConstant = 1 / (2 * Double.pi * cutoff)
        return 1 / (1 + timeConstant / elapsed)
    }

    private static func angularDifference(from start: Double, to end: Double) -> Double {
        wrapped(end - start)
    }

    private static func wrapped(_ angle: Double) -> Double {
        atan2(sin(angle), cos(angle))
    }
}
