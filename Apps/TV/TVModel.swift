import Combine
import Foundation
import StrideCore

final class TVModel: ObservableObject {
    enum SceneMode: String, CaseIterable, Identifiable {
        case trail = "內建 3D 林間路線"
        case video = "平面實景影片"
        case panorama = "360° 等距柱狀影片"
        var id: String { rawValue }
    }
    let link = LocalLink()
    let trail = TrailRenderer()
    let video = VideoRenderer()
    @Published private(set) var snapshot = PlaybackSnapshot()
    @Published private(set) var mode = SceneMode.trail
    @Published var notice: String?
    private var engine = PlaybackEngine()
    private var timer: Timer?
    private var recordedSpeed = 1.3

    init() {
        link.onConnected = { [weak self] in self?.engine.disconnect() }
        link.onDisconnected = { [weak self] in
            guard let self else { return }
            self.engine.disconnect(); self.refresh()
        }
        link.onPacket = { [weak self] packet in
            guard let self else { return }
            if !self.engine.receive(packet, at: ProcessInfo.processInfo.systemUptime) {
                self.link.disconnect() // invalid/replayed state never refreshes liveness
            }
            self.refresh()
        }
        video.onFailure = { [weak self] message in
            self?.notice = message; self?.pause(true)
        }
    }

    func start() {
        guard timer == nil else { return }
        link.startServer()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.engine.tick(at: ProcessInfo.processInfo.systemUptime)
            self.trail.update(distance: self.engine.snapshot.distance)
            self.refresh()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate(); timer = nil
        engine.disconnect(); link.stop(); refresh()
    }

    func pause(_ paused: Bool) { engine.setPaused(paused); refresh() }
    func togglePause() { pause(!engine.snapshot.paused) }
    func reset() { engine.resetDistance(); trail.update(distance: 0); refresh() }
    func rotatePairing() { engine.disconnect(); link.startServer(); refresh() }

    func configure(mode: SceneMode, url: String, recordedSpeed: Double) -> Bool {
        guard recordedSpeed.isFinite, (0.1...6).contains(recordedSpeed) else { return false }
        if mode == .trail { video.close() }
        else {
            guard let source = MediaPolicy.videoURL(url.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                notice = "請輸入不含帳號密碼的 HTTPS 影片網址。"
                return false
            }
            video.open(source)
        }
        self.mode = mode; self.recordedSpeed = recordedSpeed
        notice = nil
        pause(true) // applying a new source never autoplays; resume intentionally
        return true
    }

    private func refresh() {
        snapshot = engine.snapshot
        video.setSpeed(mode == .trail ? 0 : snapshot.speed, recordedSpeed: recordedSpeed)
    }
    deinit { timer?.invalidate() }
}
