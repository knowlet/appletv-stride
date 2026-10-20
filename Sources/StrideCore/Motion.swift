import Foundation

public struct MotionEstimate: Equatable, Sendable {
    public var cadence: Double
    public var confidence: Double
    public var steps: UInt64
    public var isMoving: Bool
    public static let stopped = Self(cadence: 0, confidence: 0, steps: 0, isMoving: false)

    public init(cadence: Double, confidence: Double, steps: UInt64, isMoving: Bool) {
        self.cadence = cadence
        self.confidence = confidence
        self.steps = steps
        self.isMoving = isMoving
    }
}

/// A heuristic for a phone secured near the hips. Not a medical/fitness distance estimator.
/// Input is signed vertical user acceleration in g, projected against Core Motion gravity.
public struct StepDetector: Sendable {
    public var threshold: Double
    private var filtered = 0.0
    private var armed = true
    private var previousSample: Double?
    private var lastPeak: Double?
    private var intervals: [Double] = []
    private var steps: UInt64 = 0
    private let minimumInterval = 0.25
    private let maximumInterval = 1.5

    public init(threshold: Double = 0.055) {
        self.threshold = threshold.isFinite ? min(0.3, max(0.02, threshold)) : 0.055
    }

    public mutating func reset() { self = Self(threshold: threshold) }

    public mutating func ingest(verticalAcceleration: Double, at time: Double) {
        guard time.isFinite, verticalAcceleration.isFinite,
              abs(verticalAcceleration) <= 8 else { return }
        if let previousSample {
            guard time > previousSample else { return }
            if time - previousSample > 2 {
                let total = steps
                reset()
                steps = total
            }
        }
        let dt = min(0.1, max(0.001, time - (previousSample ?? time - 0.02)))
        previousSample = time
        let alpha = 1 - exp(-dt / 0.035)
        filtered += alpha * (verticalAcceleration - filtered)
        let limit = threshold.isFinite ? min(0.3, max(0.02, threshold)) : 0.055
        if filtered < limit * 0.25 { armed = true }
        guard armed, filtered > limit else { return }
        armed = false
        if let lastPeak {
            let interval = time - lastPeak
            guard interval >= minimumInterval else { return }
            if interval <= maximumInterval {
                intervals.append(interval)
                if intervals.count > 6 { intervals.removeFirst() }
            } else {
                intervals.removeAll(keepingCapacity: true)
            }
        }
        lastPeak = time
        steps &+= 1
    }

    public func estimate(at time: Double) -> MotionEstimate {
        guard time.isFinite, let lastPeak, time >= lastPeak, intervals.count >= 2 else {
            return MotionEstimate(cadence: 0, confidence: 0, steps: steps, isMoving: false)
        }
        let sorted = intervals.sorted()
        let median = sorted[sorted.count / 2]
        // Slow marching needs longer than 500 ms between steps. Never infer a stop
        // before the next expected step simply because the user is moving slowly.
        let stopAfter = min(1.8, max(0.8, median * 1.7))
        guard time - lastPeak < stopAfter else {
            return MotionEstimate(cadence: 0, confidence: 0, steps: steps, isMoving: false)
        }
        let deviation = intervals.reduce(0) { $0 + abs($1 - median) } / Double(intervals.count)
        let confidence = min(1, max(0, 1 - deviation / median))
        let moving = confidence >= 0.6
        return MotionEstimate(cadence: moving ? min(240, 60 / median) : 0,
                              confidence: confidence, steps: steps, isMoving: moving)
    }
}
