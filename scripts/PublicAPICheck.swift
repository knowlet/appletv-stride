import Foundation
import StrideCore

func publicAPIContract() throws {
    let estimate = MotionEstimate(cadence: 120, confidence: 1, steps: 3, isMoving: true)
    let packet = MotionPacket(session: UUID(), sequence: 1, estimate: estimate)
    var engine = PlaybackEngine()
    _ = engine.receive(packet, at: 0)
    engine.tick(at: 0.1)
    var decoder = FrameDecoder()
    _ = try decoder.ingest(packet.framed())
    _ = try PairingCode(service: "Stride-Test", key: String(repeating: "a", count: 32))
    _ = try Route(points: [RoutePoint(x: 0, z: 0), RoutePoint(x: 0, z: -10)])
}
