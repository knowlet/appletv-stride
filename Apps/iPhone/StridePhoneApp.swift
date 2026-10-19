import SwiftUI
import StrideCore

@main
struct StridePhoneApp: App {
    @StateObject private var model = MotionController()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            PhoneView(model: model, link: model.link)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.link.browse() } else { model.deactivate() }
                }
        }
    }
}

private struct PhoneView: View {
    @ObservedObject var model: MotionController
    @ObservedObject var link: LocalLink
    @State private var scanning = false
    @State private var selectedService = ""
    @State private var secret = ""
    @State private var scannerError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("APPLE TV 連線") {
                    Label(link.status, systemImage: link.connected ? "checkmark.shield" : "tv")
                    Button("掃描電視上的配對 QR Code", systemImage: "qrcode.viewfinder") { scanning = true }
                    if link.connected { Button("中斷連線", role: .destructive) { model.stop(); link.disconnect() } }
                    DisclosureGroup("手動輸入配對碼") {
                        Picker("Apple TV", selection: $selectedService) {
                            Text("選擇裝置").tag("")
                            ForEach(link.peers) { peer in Text(peer.name).tag(peer.name) }
                        }
                        SecureField("電視顯示的 32 位英數碼", text: $secret)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("配對") {
                            do {
                                let code = try PairingCode(service: selectedService,
                                    key: secret.filter { !$0.isWhitespace })
                                model.stop(); link.connect(pairing: code); secret = ""; scannerError = nil
                            } catch { scannerError = "請選擇裝置並輸入完整的 32 位十六進位配對碼。" }
                        }
                    }
                    if let scannerError { Text(scannerError).foregroundStyle(.red) }
                }
                Section("運動控制") {
                    LabeledContent("狀態", value: model.running ? (model.estimate.isMoving ? "正在前進" : "等待穩定步伐") : "已停止")
                    LabeledContent("步頻", value: String(format: "%.0f 步／分鐘", model.estimate.cadence))
                    LabeledContent("訊號信心", value: String(format: "%.0f%%", model.estimate.confidence * 100))
                    Button(model.running ? "停止運動" : "開始感測", systemImage: model.running ? "stop.circle.fill" : "figure.walk") {
                        if model.running { model.stop() } else { model.start() }
                    }.disabled(!link.connected)
                    if let error = model.error { Text(error).foregroundStyle(.red) }
                    Text("將手機固定在腰部附近或不晃動的褲袋。App 必須保持前景；鎖定螢幕或切換 App 會停止。此為原型，不是醫療或精準計步工具。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("感測器校準") {
                    LabeledContent("啟動門檻", value: String(format: "%.3f g", model.threshold))
                    Slider(value: $model.threshold, in: 0.02...0.20, step: 0.005).disabled(model.running)
                    Text("幅度較小可降低門檻，但誤判風險也會增加。需先以自己的原地踏步／超慢跑動作測試。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("開發測試 — 非真實運動資料") {
                    Toggle("模擬步頻", isOn: $model.simulation).disabled(model.running)
                    if model.simulation {
                        LabeledContent("模擬步頻", value: "\(Int(model.simulatedCadence)) 步／分鐘")
                        Slider(value: $model.simulatedCadence, in: 40...220, step: 10).disabled(model.running)
                    }
                }
                Section("資料處理") {
                    Text("運動控制僅走區域網路的配對加密連線，不上傳雲端。沒有 Apple Watch、心率或 HealthKit 紀錄功能。")
                        .font(.footnote)
                }
            }
            .navigationTitle("Stride Controller")
            .task { link.browse() }
            .sheet(isPresented: $scanning) {
                ZStack(alignment: .topTrailing) {
                    PairingScanner { value in
                        scanning = false
                        do {
                            let code = try PairingCode(url: value)
                            model.stop(); link.connect(pairing: code); scannerError = nil
                        } catch { scannerError = "這不是有效的 Stride 配對 QR Code。" }
                    } onError: { error in scanning = false; scannerError = error }
                    Button("關閉") { scanning = false }.buttonStyle(.borderedProminent).padding()
                }.ignoresSafeArea()
            }
        }
    }
}
