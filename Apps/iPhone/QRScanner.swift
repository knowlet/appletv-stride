import AVFoundation
import SwiftUI
import UIKit

struct PairingScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onError: (String) -> Void
    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.onCode = onCode; controller.onError = onError
        return controller
    }
    func updateUIViewController(_ uiViewController: ScannerController, context: Context) {}
    static func dismantleUIViewController(_ controller: ScannerController, coordinator: ()) { controller.stop() }
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    var onError: ((String) -> Void)?
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "stride.qr.camera")
    private var preview: AVCaptureVideoPreviewLayer?
    private var finished = false
    private var configured = false // access only on camera queue

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        self.preview = preview
        view.layer.addSublayer(preview)
        AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
            DispatchQueue.main.async {
                guard let self, !self.finished else { return }
                guard allowed else { self.onError?("未取得相機權限；可改用手動配對碼。"); return }
                self.configure()
            }
        }
    }

    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }

    private func configure() {
        queue.async { [weak self] in
            guard let self, !self.configured else { return }
            self.session.beginConfiguration()
            do {
                guard let camera = AVCaptureDevice.default(for: .video) else { throw ScannerError.unavailable }
                let input = try AVCaptureDeviceInput(device: camera)
                let output = AVCaptureMetadataOutput()
                guard self.session.canAddInput(input), self.session.canAddOutput(output) else { throw ScannerError.unavailable }
                self.session.addInput(input); self.session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                guard output.availableMetadataObjectTypes.contains(.qr) else { throw ScannerError.unavailable }
                output.metadataObjectTypes = [.qr]
                self.configured = true
                self.session.commitConfiguration()
                self.session.startRunning()
            } catch {
                self.session.commitConfiguration()
                DispatchQueue.main.async { [weak self] in self?.onError?("無法啟動 QR 掃描；請使用手動配對。"); }
            }
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !finished, let value = objects.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first else { return }
        finished = true
        queue.async { [session] in session.stopRunning() }
        onCode?(value) // PairingCode validates scheme, size, fields, and key length.
    }

    func stop() {
        finished = true
        queue.async { [session] in session.stopRunning() }
    }
    private enum ScannerError: Error { case unavailable }
}
