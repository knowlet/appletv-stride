import AVFoundation
import SceneKit
import StrideCore
import SwiftUI
import UIKit

/// Original, deterministic procedural content: no downloaded scenery or map license.
final class TrailRenderer {
    let scene = SCNScene()
    let camera = SCNNode()
    let route = Route.demo

    init() {
        scene.background.contents = UIColor(red: 0.56, green: 0.76, blue: 0.87, alpha: 1)
        scene.fogColor = UIColor(red: 0.65, green: 0.80, blue: 0.83, alpha: 1)
        scene.fogStartDistance = 65; scene.fogEndDistance = 150
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 78
        camera.camera?.zFar = 250
        scene.rootNode.addChildNode(camera)

        let ambient = SCNNode()
        ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.intensity = 650
        scene.rootNode.addChildNode(ambient)
        let sun = SCNNode()
        sun.light = SCNLight(); sun.light?.type = .directional; sun.light?.intensity = 1100
        sun.eulerAngles = SCNVector3(-Float.pi / 3, -Float.pi / 4, 0)
        scene.rootNode.addChildNode(sun)

        let ground = SCNPlane(width: 400, height: 400)
        ground.firstMaterial?.diffuse.contents = UIColor(red: 0.31, green: 0.46, blue: 0.29, alpha: 1)
        let groundNode = SCNNode(geometry: ground)
        groundNode.eulerAngles.x = -.pi / 2
        scene.rootNode.addChildNode(groundNode)

        let pathMaterial = SCNMaterial()
        pathMaterial.diffuse.contents = UIColor(red: 0.75, green: 0.67, blue: 0.51, alpha: 1)
        for index in 1..<route.points.count {
            let a = route.points[index - 1], b = route.points[index]
            let length = hypot(b.x - a.x, b.z - a.z)
            let geometry = SCNBox(width: 4.8, height: 0.025, length: CGFloat(length + 0.1), chamferRadius: 0)
            geometry.materials = [pathMaterial]
            let node = SCNNode(geometry: geometry)
            node.position = SCNVector3(Float((a.x + b.x) / 2), 0.025, Float((a.z + b.z) / 2))
            node.eulerAngles.y = Float(atan2(b.x - a.x, b.z - a.z))
            scene.rootNode.addChildNode(node)
        }
        for i in 0..<140 {
            let angle = Double(i) * 2.3999632297
            let radius = i.isMultiple(of: 2) ? 91 + Double(i % 19) : 45 + Double(i % 23)
            let height = 4.5 + Double(i % 7) * 0.55
            let tree = SCNNode()
            let trunk = SCNCylinder(radius: 0.20, height: CGFloat(height / 3))
            trunk.firstMaterial?.diffuse.contents = UIColor(red: 0.34, green: 0.24, blue: 0.17, alpha: 1)
            let trunkNode = SCNNode(geometry: trunk)
            trunkNode.position.y = Float(height / 6)
            tree.addChildNode(trunkNode)
            let crown = SCNCone(topRadius: 0, bottomRadius: CGFloat(height * 0.34), height: CGFloat(height))
            crown.radialSegmentCount = 7
            crown.firstMaterial?.diffuse.contents = UIColor(red: 0.12 + Double(i % 3) * 0.02, green: 0.31, blue: 0.20, alpha: 1)
            let crownNode = SCNNode(geometry: crown)
            crownNode.position.y = Float(height * 0.68)
            tree.addChildNode(crownNode)
            tree.position = SCNVector3(Float(radius * sin(angle)), 0, Float(radius * cos(angle)))
            scene.rootNode.addChildNode(tree)
        }
        update(distance: 0)
    }

    func update(distance: Double) {
        let pose = route.pose(at: distance)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        camera.position = SCNVector3(Float(pose.point.x), 1.65, Float(pose.point.z))
        camera.eulerAngles = SCNVector3(0, Float(pose.yaw), 0)
        SCNTransaction.commit()
    }
}

struct NativeScene: UIViewRepresentable {
    let scene: SCNScene
    let camera: SCNNode
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = scene; view.pointOfView = camera
        view.preferredFramesPerSecond = 30
        view.antialiasingMode = .multisampling4X
        view.isPlaying = true
        view.allowsCameraControl = false
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) {
        if view.scene !== scene { view.scene = scene; view.pointOfView = camera }
    }
    static func dismantleUIView(_ view: SCNView, coordinator: ()) {
        view.isPlaying = false; view.scene = nil
    }
}

final class VideoRenderer {
    let player = AVPlayer()
    let scene = SCNScene()
    let camera = SCNNode()
    var onFailure: ((String) -> Void)?
    private var statusObservation: NSKeyValueObservation?
    private var endObservation: NSObjectProtocol?
    private var requestedRate: Float = 0
    private var yaw: Float = 0

    init() {
        player.isMuted = true // variable-rate scenery; no distorted audio
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 80
        scene.rootNode.addChildNode(camera)
        let sphere = SCNSphere(radius: 10)
        sphere.segmentCount = 96
        let material = SCNMaterial()
        material.diffuse.contents = player
        material.lightingModel = .constant
        material.cullMode = .front
        // Viewed from inside a mono 2:1 equirectangular sphere.
        material.diffuse.contentsTransform = SCNMatrix4MakeScale(-1, 1, 1)
        material.diffuse.wrapS = .repeat
        sphere.materials = [material]
        scene.rootNode.addChildNode(SCNNode(geometry: sphere))
    }

    func open(_ url: URL) {
        close()
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self, weak item] _, _ in
            DispatchQueue.main.async {
                guard let self, let item, self.player.currentItem === item else { return }
                if item.status == .readyToPlay { self.applyRate() }
                if item.status == .failed { self.onFailure?("影片無法播放；請確認 HTTPS、格式與來源授權。") }
            }
        }
        endObservation = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
            object: item, queue: .main) { [weak self] _ in
                self?.onFailure?("影片已結束。重新套用影片來源可從頭播放。")
            }
    }

    func setSpeed(_ speed: Double, recordedSpeed: Double) {
        let next = MediaPolicy.rate(speed: speed, recordedSpeed: recordedSpeed)
        guard next != requestedRate else { return }
        requestedRate = next
        applyRate()
    }

    private func applyRate() {
        if requestedRate == 0 { player.pause() }
        else if player.currentItem?.status == .readyToPlay { player.rate = requestedRate }
    }

    func turn(by angle: Float) { yaw += angle; camera.eulerAngles.y = yaw }

    func close() {
        requestedRate = 0; player.pause()
        statusObservation?.invalidate(); statusObservation = nil
        if let endObservation { NotificationCenter.default.removeObserver(endObservation) }
        endObservation = nil
        player.replaceCurrentItem(with: nil)
    }

    deinit { close() }
}

final class PlayerSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

/// No standalone playback controls: motion/TV pause remain the only play authorities.
struct FlatVideo: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerSurface {
        let view = PlayerSurface()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }
    func updateUIView(_ view: PlayerSurface, context: Context) { view.playerLayer.player = player }
    static func dismantleUIView(_ view: PlayerSurface, coordinator: ()) { view.playerLayer.player = nil }
}
