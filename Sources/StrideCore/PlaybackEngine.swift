import Foundation

public struct PlaybackSnapshot: Equatable, Sendable {
    public var speed: Double = 0
    public var distance: Double = 0
    public var cadence: Double = 0
    public var steps: UInt64 = 0
    public var paused: Bool = false
    public var sourceFresh: Bool = false
    public init() {}
}

/// Pure deterministic state machine. All times are receiver-local monotonic seconds.
/// Distance is a virtual route control value, not measured outdoor travel.
public struct PlaybackEngine: Sendable {
    public private(set) var snapshot = PlaybackSnapshot()
    public let stepLength: Double
    public let staleAfter: Double
    private var lastReceived: Double?
    private var lastTick: Double?
    private var session: UUID?
    private var sequence: UInt64?
    private var targetSpeed = 0.0
    private var lastSteps: UInt64?
    private var stepOffset: UInt64 = 0

    public init(stepLength: Double = 0.65, staleAfter: Double = 1.2) {
        self.stepLength = stepLength.isFinite ? min(1.5, max(0.1, stepLength)) : 0.65
        self.staleAfter = staleAfter.isFinite ? min(3, max(0.5, staleAfter)) : 1.2
    }

    @discardableResult
    public mutating func receive(_ packet: MotionPacket, at time: Double) -> Bool {
        guard time.isFinite, (try? packet.validate()) != nil else { return false }
        if let lastReceived, time < lastReceived { return false }
        if let session, packet.session != session { return false }
        if let sequence, packet.sequence <= sequence { return false }
        if let lastSteps, packet.steps < lastSteps { return false }
        if session == nil { stepOffset = packet.steps }
        session = packet.session
        sequence = packet.sequence
        lastSteps = packet.steps
        lastReceived = time
        snapshot.sourceFresh = true
        snapshot.steps = packet.steps - stepOffset
        snapshot.cadence = packet.moving ? packet.cadence : 0
        targetSpeed = packet.moving && !snapshot.paused ? packet.cadence * stepLength / 60 : 0
        if targetSpeed == 0 { snapshot.speed = 0 }
        return true
    }

    public mutating func tick(at time: Double) {
        guard time.isFinite else { return }
        if let lastTick, time <= lastTick { return }
        let elapsed = time - (lastTick ?? time)
        lastTick = time
        snapshot.sourceFresh = lastReceived.map { time >= $0 && time - $0 < staleAfter } ?? false
        guard snapshot.sourceFresh, !snapshot.paused, elapsed <= 0.5 else {
            snapshot.speed = 0
            if !snapshot.sourceFresh || elapsed > 0.5 { targetSpeed = 0; snapshot.cadence = 0 }
            return
        }
        let dt = min(elapsed, 0.1)
        if targetSpeed == 0 { snapshot.speed = 0; return }
        snapshot.speed += (targetSpeed - snapshot.speed) * (1 - exp(-dt / 0.25))
        snapshot.distance += snapshot.speed * dt
    }

    /// A TV remote pause is latched: future incoming motion cannot override it.
    public mutating func setPaused(_ paused: Bool) {
        snapshot.paused = paused
        snapshot.speed = 0
        targetSpeed = 0 // resume requires a new valid source packet
    }

    public mutating func disconnect() {
        session = nil; sequence = nil; lastReceived = nil; lastSteps = nil
        targetSpeed = 0
        snapshot.speed = 0; snapshot.cadence = 0; snapshot.sourceFresh = false
    }

    public mutating func resetDistance() {
        snapshot.distance = 0; snapshot.steps = 0
        stepOffset = lastSteps ?? 0
    }
}
