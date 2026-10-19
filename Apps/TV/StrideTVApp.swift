import CoreImage.CIFilterBuiltins
import StrideCore
import SwiftUI

@main
struct StrideTVApp: App {
    @StateObject private var model = TVModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            StrideTVView(model: model, link: model.link)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.start() } else { model.stop() }
                }
        }
    }
}

private struct StrideTVView: View {
    @ObservedObject var model: TVModel
    @ObservedObject var link: LocalLink
    @State private var pairingVisible = true
    @State private var settingsVisible = false
    var body: some View {
        ZStack {
            Group {
                switch model.mode {
                case .trail: NativeScene(scene: model.trail.scene, camera: model.trail.camera)
                case .video: FlatVideo(player: model.video.player)
                case .panorama: NativeScene(scene: model.video.scene, camera: model.video.camera)
                }
            }.ignoresSafeArea()
            VStack {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("STRIDE").font(.title2.bold())
                        Text(model.mode.rawValue).font(.caption)
                        Text(link.status).font(.caption2)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        Text(model.snapshot.paused ? "已暫停" : model.snapshot.speed > 0 ? "正在前進" : "等待步伐")
                            .font(.headline)
                        Text(String(format: "%.0f 步／分  ·  %.2f m/s", model.snapshot.cadence, model.snapshot.speed))
                            .monospacedDigit()
                        Text(String(format: "虛擬距離 %.0f m", model.snapshot.distance)).monospacedDigit()
                    }
                }.padding(24).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                Spacer()
                if let notice = model.notice {
                    Text(notice).padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                HStack(spacing: 24) {
                    Button("配對手機", systemImage: "qrcode") { pairingVisible = true }
                    Button(model.snapshot.paused ? "恢復" : "暫停", systemImage: model.snapshot.paused ? "play.fill" : "pause.fill") {
                        model.togglePause()
                    }
                    Button("重設距離", systemImage: "arrow.counterclockwise") { model.reset() }
                    Button("選擇場景", systemImage: "mountain.2") { model.pause(true); settingsVisible = true }
                }
            }.padding(44)
        }
        .task { model.start() }
        .onPlayPauseCommand { model.togglePause() }
        .onMoveCommand { direction in
            guard model.mode == .panorama, !pairingVisible, !settingsVisible else { return }
            if direction == .left { model.video.turn(by: .pi / 12) }
            if direction == .right { model.video.turn(by: -.pi / 12) }
        }
        .onChange(of: link.connected) { _, connected in if connected { pairingVisible = false } }
        .sheet(isPresented: $pairingVisible) { PairingView(link: link, rotate: model.rotatePairing) }
        .sheet(isPresented: $settingsVisible) { SceneSettings(model: model) }
    }
}

private struct PairingView: View {
    @ObservedObject var link: LocalLink
    let rotate: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 24) {
            Text("讓步伐帶動風景").font(.largeTitle.bold())
            Text("iPhone 與 Apple TV 連上同一網路，在 Stride Controller 掃描此 QR Code。")
            if let pairing = link.pairing {
                HStack(spacing: 40) {
                    if let image = qrImage(pairing.url) {
                        Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                            .frame(width: 300, height: 300).padding(18).background(.white)
                    }
                    VStack(alignment: .leading, spacing: 20) {
                        Text(pairing.service).font(.caption).monospaced()
                        Text("手動配對碼").font(.headline)
                        Text(grouped(pairing.key)).font(.title3.monospaced())
                        Text("配對碼含連線密鑰；請勿公開截圖。\n每次重新啟動或更新配對都會更換。").font(.caption)
                    }
                }
            }
            Text(link.status).font(.headline)
            HStack {
                Button("更新配對碼", action: rotate)
                Button("關閉") { dismiss() }
            }
        }.padding(50)
    }
    private func grouped(_ key: String) -> String {
        stride(from: 0, to: key.count, by: 8).map { offset in
            String(key.dropFirst(offset).prefix(8))
        }.joined(separator: " ")
    }
    private func qrImage(_ string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: image)
    }
}

private struct SceneSettings: View {
    @ObservedObject var model: TVModel
    @State private var mode = TVModel.SceneMode.trail
    @State private var url = ""
    @State private var recordedSpeed = 1.3
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Picker("場景", selection: $mode) {
                    ForEach(TVModel.SceneMode.allCases) { value in Text(value.rawValue).tag(value) }
                }
                if mode != .trail {
                    TextField("有權使用的 HTTPS MP4 / HLS 影片網址", text: $url)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Picker("拍攝時的參考前進速度", selection: $recordedSpeed) {
                        Text("慢走 · 0.8 m/s").tag(0.8)
                        Text("步行 · 1.3 m/s").tag(1.3)
                        Text("慢跑 · 2.0 m/s").tag(2.0)
                    }
                    Text("360° 模式只支援單眼 2:1 等距柱狀影片；左右鍵調整視角。定點 360° 影片只能轉頭，不能產生實際前進視差。")
                    Text("影片不隨 App 提供；請自行確認授權。播放倍率限制為 0.25–2 倍，緩衝與倍率上限可能讓影片進度與虛擬距離不同。")
                } else {
                    Text("完全離線的自製 3D 林間環狀路線，與專案程式碼同採 MIT 授權。")
                }
                if let notice = model.notice { Text(notice).foregroundStyle(.red) }
                Button("套用並關閉") {
                    if model.configure(mode: mode, url: url, recordedSpeed: recordedSpeed) { dismiss() }
                }
                Button("取消") { dismiss() }
            }.navigationTitle("場景設定")
        }.onAppear { mode = model.mode }
    }
}
