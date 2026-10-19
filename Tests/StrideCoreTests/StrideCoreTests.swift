import Foundation
import XCTest
@testable import StrideCore

final class MotionTests: XCTestCase {
    private func walk(cadence: Double, seconds: Double = 8) -> StepDetector {
        var detector = StepDetector()
        for i in 0...Int(seconds * 50) {
            let t = Double(i) / 50
            detector.ingest(verticalAcceleration: 0.15 * sin(2 * .pi * cadence / 60 * t), at: t)
        }
        return detector
    }
    func testWalking60() {
        let result = walk(cadence: 60).estimate(at: 8)
        XCTAssertTrue(result.isMoving)
        XCTAssertEqual(result.cadence, 60, accuracy: 3)
    }
    func testWalking120() {
        XCTAssertEqual(walk(cadence: 120).estimate(at: 8).cadence, 120, accuracy: 3)
    }
    func testJogging180() {
        XCTAssertEqual(walk(cadence: 180).estimate(at: 8).cadence, 180, accuracy: 7)
    }
    func testStopsWithoutFurtherSamples() {
        XCTAssertFalse(walk(cadence: 120).estimate(at: 10).isMoving)
    }
    func testSlowStepsDoNotStopBetweenPeaks() {
        let detector = walk(cadence: 60, seconds: 7.3)
        XCTAssertTrue(detector.estimate(at: 8).isMoving)
    }
    func testNoiseDoesNotStart() {
        var detector = StepDetector()
        for i in 0..<500 {
            detector.ingest(verticalAcceleration: 0.009 * sin(Double(i)), at: Double(i) / 50)
        }
        XCTAssertFalse(detector.estimate(at: 10).isMoving)
    }
    func testSingleBumpDoesNotStart() {
        var detector = StepDetector()
        detector.ingest(verticalAcceleration: 0.5, at: 1)
        XCTAssertFalse(detector.estimate(at: 1.1).isMoving)
    }
    func testInvalidSamplesDoNotPoisonState() {
        var detector = walk(cadence: 120)
        detector.ingest(verticalAcceleration: .nan, at: 8.1)
        detector.ingest(verticalAcceleration: 1, at: .infinity)
        detector.ingest(verticalAcceleration: 1, at: 7)
        XCTAssertTrue(detector.estimate(at: 8.1).cadence.isFinite)
        XCTAssertFalse(detector.estimate(at: .nan).isMoving)
    }
    func testSampleGapPreservesCounter() {
        var detector = walk(cadence: 120)
        let before = detector.estimate(at: 8).steps
        detector.ingest(verticalAcceleration: 0, at: 12)
        XCTAssertEqual(detector.estimate(at: 12).steps, before)
        XCTAssertFalse(detector.estimate(at: 12).isMoving)
    }
    func testInvalidThresholdIsClamped() {
        var detector = StepDetector(threshold: .nan)
        detector.threshold = -.infinity
        detector.ingest(verticalAcceleration: 0, at: 1)
        XCTAssertFalse(detector.estimate(at: 1).isMoving)
    }
}

final class ProtocolTests: XCTestCase {
    private func packet(_ seq: UInt64 = 1) -> MotionPacket {
        MotionPacket(session: UUID(), sequence: seq,
                     estimate: MotionEstimate(cadence: 120, confidence: 1, steps: 10, isMoving: true))
    }
    func testRoundTrip() throws {
        let original = packet()
        var decoder = FrameDecoder()
        XCTAssertEqual(try decoder.ingest(original.framed()), [original])
    }
    func testEveryPossibleSplit() throws {
        let original = packet()
        let bytes = try original.framed()
        for split in 0...bytes.count {
            var decoder = FrameDecoder()
            let a = try decoder.ingest(Data(bytes.prefix(split)))
            let b = try decoder.ingest(Data(bytes.dropFirst(split)))
            XCTAssertEqual(a + b, [original])
        }
    }
    func testCoalescedPackets() throws {
        let a = packet(1), b = packet(2)
        var decoder = FrameDecoder()
        XCTAssertEqual(try decoder.ingest(a.framed() + b.framed()), [a, b])
    }
    func testPartialFrameIsBounded() throws {
        var decoder = FrameDecoder()
        XCTAssertEqual(try decoder.ingest(Data(repeating: 32, count: 4096)), [])
        XCTAssertThrowsError(try decoder.ingest(Data([32])))
    }
    func testHugeChunkRejected() {
        var decoder = FrameDecoder()
        XCTAssertThrowsError(try decoder.ingest(Data(repeating: 32, count: 16385)))
    }
    func testBlankFrameRejected() {
        var decoder = FrameDecoder()
        XCTAssertThrowsError(try decoder.ingest(Data([10])))
    }
    func testMalformedJSONRejected() {
        var decoder = FrameDecoder()
        XCTAssertThrowsError(try decoder.ingest(Data("not-json\n".utf8)))
    }
    func testUnsupportedVersion() throws {
        var decoder = FrameDecoder()
        let json = String(data: try packet().framed(), encoding: .utf8)!.replacingOccurrences(of: "\"version\":1", with: "\"version\":9")
        XCTAssertThrowsError(try decoder.ingest(Data(json.utf8)))
    }
    func testInvalidMovingPacket() {
        let value = MotionPacket(session: UUID(), sequence: 1,
                                 estimate: MotionEstimate(cadence: 0, confidence: 1, steps: 0, isMoving: true))
        XCTAssertThrowsError(try value.validate())
    }
    func testInvalidStopPacket() {
        let value = MotionPacket(session: UUID(), sequence: 1,
                                 estimate: MotionEstimate(cadence: 120, confidence: 1, steps: 0, isMoving: false))
        XCTAssertThrowsError(try value.validate())
    }
    func testNonFiniteCadenceRejected() {
        let value = MotionPacket(session: UUID(), sequence: 1,
                                 estimate: MotionEstimate(cadence: .nan, confidence: 1, steps: 0, isMoving: true))
        XCTAssertThrowsError(try value.validate())
    }
    func testLowConfidenceRejected() {
        let value = MotionPacket(session: UUID(), sequence: 1,
                                 estimate: MotionEstimate(cadence: 120, confidence: 0.2, steps: 0, isMoving: true))
        XCTAssertThrowsError(try value.validate())
    }
    func testPairingRoundTrip() throws {
        let code = try PairingCode(service: "Stride-ABCD1234", key: "0123456789ABCDEFFEDCBA9876543210")
        XCTAssertEqual(try PairingCode(url: code.url), code)
        XCTAssertEqual(code.secret.count, 16)
        XCTAssertEqual(code.secret.first, 1)
    }
    func testPairingRejectsWrongSchemeAndDuplicateParameters() throws {
        let code = try PairingCode(service: "Stride-ABCD1234", key: String(repeating: "a", count: 32))
        XCTAssertThrowsError(try PairingCode(url: code.url.replacingOccurrences(of: "stride:", with: "https:")))
        XCTAssertThrowsError(try PairingCode(url: code.url + "&key=" + code.key))
        XCTAssertThrowsError(try PairingCode(url: code.url + "#secret"))
    }
    func testPairingRejectsShortOrInvalidSecret() {
        XCTAssertThrowsError(try PairingCode(service: "Stride-ABCD", key: "123456"))
        XCTAssertThrowsError(try PairingCode(service: "Stride-ABCD", key: String(repeating: "z", count: 32)))
        XCTAssertThrowsError(try PairingCode(service: "evil/service", key: String(repeating: "0", count: 32)))
    }
}

final class PlaybackTests: XCTestCase {
    private let session = UUID()
    private func packet(_ sequence: UInt64, moving: Bool = true, steps: UInt64 = 10) -> MotionPacket {
        MotionPacket(session: session, sequence: sequence,
                     estimate: MotionEstimate(cadence: moving ? 120 : 0, confidence: 1, steps: steps, isMoving: moving))
    }
    func testMotionAdvancesDistance() {
        var engine = PlaybackEngine()
        XCTAssertTrue(engine.receive(packet(1), at: 0))
        for i in 0...10 { engine.tick(at: Double(i) / 10) }
        XCTAssertGreaterThan(engine.snapshot.distance, 0.7)
        XCTAssertLessThan(engine.snapshot.speed, 1.31)
    }
    func testExplicitStopIsImmediate() {
        var engine = PlaybackEngine()
        engine.receive(packet(1), at: 0); engine.tick(at: 0); engine.tick(at: 0.1)
        XCTAssertGreaterThan(engine.snapshot.speed, 0)
        engine.receive(packet(2, moving: false), at: 0.2)
        XCTAssertEqual(engine.snapshot.speed, 0)
    }
    func testStaleSourceStops() {
        var engine = PlaybackEngine()
        engine.receive(packet(1), at: 0)
        for i in 0...20 { engine.tick(at: Double(i) / 10) }
        XCTAssertEqual(engine.snapshot.speed, 0)
        XCTAssertFalse(engine.snapshot.sourceFresh)
    }
    func testReplayedPacketCannotKeepSourceAlive() {
        var engine = PlaybackEngine()
        engine.receive(packet(1), at: 0)
        XCTAssertFalse(engine.receive(packet(1), at: 1))
        engine.tick(at: 1.3)
        XCTAssertFalse(engine.snapshot.sourceFresh)
    }
    func testReorderedPacketRejected() {
        var engine = PlaybackEngine()
        engine.receive(packet(2), at: 0)
        XCTAssertFalse(engine.receive(packet(1), at: 0.1))
    }
    func testCounterRollbackRejected() {
        var engine = PlaybackEngine()
        engine.receive(packet(1, steps: 20), at: 0)
        XCTAssertFalse(engine.receive(packet(2, steps: 19), at: 0.1))
    }
    func testForeignSessionRejectedUntilDisconnect() {
        var engine = PlaybackEngine()
        engine.receive(packet(1), at: 0)
        let other = MotionPacket(session: UUID(), sequence: 1, estimate: .stopped)
        XCTAssertFalse(engine.receive(other, at: 0.1))
        engine.disconnect()
        XCTAssertTrue(engine.receive(other, at: 0.2))
    }
    func testPauseIsLatched() {
        var engine = PlaybackEngine()
        engine.setPaused(true)
        engine.receive(packet(1), at: 0); engine.tick(at: 0); engine.tick(at: 0.1)
        XCTAssertEqual(engine.snapshot.speed, 0)
        XCTAssertTrue(engine.snapshot.paused)
        engine.setPaused(false)
        engine.tick(at: 0.2)
        XCTAssertEqual(engine.snapshot.speed, 0)
        engine.receive(packet(2), at: 0.3); engine.tick(at: 0.3)
        XCTAssertGreaterThan(engine.snapshot.speed, 0)
    }
    func testClockRollbackAndNaNAreRejected() {
        var engine = PlaybackEngine()
        engine.receive(packet(1), at: 1)
        XCTAssertFalse(engine.receive(packet(2), at: 0.9))
        XCTAssertFalse(engine.receive(packet(3), at: .nan))
        engine.tick(at: .nan)
        XCTAssertEqual(engine.snapshot.distance, 0)
    }
    func testSuspensionDoesNotTeleport() {
        var engine = PlaybackEngine(staleAfter: 3)
        engine.receive(packet(1), at: 0); engine.tick(at: 0)
        engine.receive(packet(2), at: 2); engine.tick(at: 2)
        XCTAssertEqual(engine.snapshot.distance, 0)
        XCTAssertEqual(engine.snapshot.speed, 0)
    }
    func testResetDistanceKeepsSourceSequenceGuard() {
        var engine = PlaybackEngine()
        engine.receive(packet(1), at: 0)
        engine.receive(packet(2, steps: 20), at: 0.1)
        XCTAssertEqual(engine.snapshot.steps, 10)
        engine.resetDistance()
        XCTAssertEqual(engine.snapshot.steps, 0)
        XCTAssertFalse(engine.receive(packet(1), at: 0.2))
        engine.receive(packet(3, steps: 23), at: 0.3)
        XCTAssertEqual(engine.snapshot.steps, 3)
    }
    func testDisconnectStopsImmediately() {
        var engine = PlaybackEngine()
        engine.receive(packet(1), at: 0); engine.tick(at: 0); engine.tick(at: 0.1)
        engine.disconnect()
        XCTAssertEqual(engine.snapshot.speed, 0)
    }
}

final class RouteTests: XCTestCase {
    func testInterpolationAndClamping() throws {
        let route = try Route(points: [.init(x: 0, z: 0), .init(x: 0, z: -10)])
        XCTAssertEqual(route.pose(at: 5).point.z, -5)
        XCTAssertEqual(route.pose(at: 12).point.z, -2)
        XCTAssertEqual(route.pose(at: 12, looping: false).point.z, -10)
        XCTAssertEqual(route.pose(at: -10).point.z, 0)
    }
    func testCameraFacesForward() throws {
        let route = try Route(points: [.init(x: 0, z: 0), .init(x: 10, z: 0)])
        XCTAssertEqual(route.pose(at: 1).yaw, -.pi / 2, accuracy: 0.001)
    }
    func testDuplicatePointsAndNonFiniteCoordinatesRejected() {
        XCTAssertThrowsError(try Route(points: [.init(x: 0, z: 0), .init(x: 0, z: 0)]))
        XCTAssertThrowsError(try Route(points: [.init(x: .nan, z: 0), .init(x: 1, z: 1)]))
        XCTAssertThrowsError(try Route(points: []))
    }
    func testDemoLoop() {
        XCTAssertEqual(Route.demo.length, 2 * .pi * 80, accuracy: 0.1)
        XCTAssertEqual(Route.demo.pose(at: Route.demo.length).point, Route.demo.pose(at: 0).point)
    }
    func testVideoPolicy() {
        XCTAssertNotNil(MediaPolicy.videoURL("https://media.example.org/walk.mp4"))
        XCTAssertNil(MediaPolicy.videoURL("http://example.org/walk.mp4"))
        XCTAssertNil(MediaPolicy.videoURL("file:///etc/passwd"))
        XCTAssertNil(MediaPolicy.videoURL("https://user:pass@example.org/walk.mp4"))
        XCTAssertNil(MediaPolicy.videoURL("https://example.org/walk.mp4#hidden"))
    }
    func testVideoRateBounds() {
        XCTAssertEqual(MediaPolicy.rate(speed: 0, recordedSpeed: 1), 0)
        XCTAssertEqual(MediaPolicy.rate(speed: .nan, recordedSpeed: 1), 0)
        XCTAssertEqual(MediaPolicy.rate(speed: 1, recordedSpeed: 0), 0)
        XCTAssertEqual(MediaPolicy.rate(speed: 10, recordedSpeed: 1), 2)
        XCTAssertEqual(MediaPolicy.rate(speed: 0.01, recordedSpeed: 1), 0.25)
    }
}
