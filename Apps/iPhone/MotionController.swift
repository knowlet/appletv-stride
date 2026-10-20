import Combine
import CoreMotion
import Foundation
import StrideCore
import UIKit

final class MotionController: ObservableObject {
    let link = LocalLink()
    @Published private(set) var estimate = MotionEstimate.stopped
    @Published private(set) var running = false
    @Published var simulation = false
    @Published var simulatedCadence = 120.0
    @Published var threshold = 0.055
    @Published var error: String?
    private let motion = CMMotionManager()
    private var detector = StepDetector()
    private var timer: Timer?
    private let session = UUID()
    private var sequence: UInt64 = 0
    private var totalSteps: UInt64 = 0
    private var offset: UInt64 = 0
    private var simulationStart = 0.0
    private var lastMotionAt: Double?

    init() {
        link.onDisconnected = { [weak self] in self?.stop() }
        // Stop packets continue at 10 Hz while paired; the TV can distinguish
        // stationary movement from a disconnected/suspended source.
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func start() {
        guard link.connected, !running else { return }
        error = nil
        offset = totalSteps
        detector = StepDetector(threshold: threshold)
        lastMotionAt = nil
        if simulation {
            simulationStart = ProcessInfo.processInfo.systemUptime
        } else {
            guard motion.isDeviceMotionAvailable else {
                error = "此裝置沒有可用的動作感測器。模擬器請使用明確標示的測試模式。"
                return
            }
            motion.deviceMotionUpdateInterval = 1.0 / 50
            motion.startDeviceMotionUpdates(to: .main) { [weak self] sample, failure in
                guard let self, self.running else { return }
                guard let sample, failure == nil else {
                    self.error = "動作資料中斷；已停止傳送運動狀態。"
                    self.stop(); return
                }
                let a = sample.userAcceleration, g = sample.gravity
                // Core Motion has already removed gravity. The dot product keeps
                // the estimator independent of the phone's portrait/landscape pose.
                let vertical = -(a.x * g.x + a.y * g.y + a.z * g.z)
                self.detector.ingest(verticalAcceleration: vertical, at: sample.timestamp)
                self.lastMotionAt = ProcessInfo.processInfo.systemUptime
            }
        }
        running = true
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        running = false
        lastMotionAt = nil
        estimate = MotionEstimate(cadence: 0, confidence: 0, steps: totalSteps, isMoving: false)
        UIApplication.shared.isIdleTimerDisabled = false
        send()
    }

    func deactivate() {
        stop()
        link.stop() // no invented iOS background entitlement / silent audio workaround
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if running {
            if simulation {
                let cadence = min(220, max(40, simulatedCadence))
                totalSteps = offset + UInt64(max(0, now - simulationStart) * cadence / 60)
                estimate = MotionEstimate(cadence: cadence, confidence: 1, steps: totalSteps, isMoving: true)
            } else if let lastMotionAt, now - lastMotionAt < 0.4 {
                var value = detector.estimate(at: now)
                value.steps += offset
                totalSteps = value.steps
                estimate = value
            } else {
                estimate = MotionEstimate(cadence: 0, confidence: 0, steps: totalSteps, isMoving: false)
            }
        }
        send()
    }

    private func send() {
        guard link.connected else { return }
        sequence &+= 1
        link.send(MotionPacket(session: session, sequence: sequence, estimate: estimate))
    }

    deinit { timer?.invalidate(); motion.stopDeviceMotionUpdates() }
}
