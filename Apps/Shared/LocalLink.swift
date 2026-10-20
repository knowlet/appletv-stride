import Combine
import Foundation
import Network
import Security
import StrideCore

struct StridePeer: Identifiable {
    let name: String
    let endpoint: NWEndpoint
    var id: String { name }
}

private enum StrideTLS {
    static func parameters(for pairing: PairingCode) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let secret = pairing.secret.withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = Data("appletv-stride-v1".utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions,
                                                secret as __DispatchData, identity as __DispatchData)
        // Match Apple's Network.framework PSK sample. A random 128-bit key, not a
        // guessable PIN. TLS 1.2 PSK-GCM has no forward secrecy; see SECURITY.md.
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_append_tls_ciphersuite(tls.securityProtocolOptions,
            tls_ciphersuite_t(rawValue: TLS_PSK_WITH_AES_128_GCM_SHA256)!)
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = false // ordinary trusted LAN; no cloud relay
        return parameters
    }

    static func newPairing() throws -> PairingCode {
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw StrideError.invalidPairingCode
        }
        return try PairingCode(service: "Stride-" + UUID().uuidString,
                               key: bytes.map { String(format: "%02x", $0) }.joined())
    }
}

/// All callbacks and mutable state live on the main queue. Receive buffers, pending
/// handshakes, packet rate, and outbound backlog are bounded independently.
private final class MotionChannel {
    let id = UUID()
    let connection: NWConnection
    var onReady: (() -> Void)?
    var onPacket: ((MotionPacket) -> Void)?
    var onClose: (() -> Void)?
    private var decoder = FrameDecoder()
    private var closed = false
    private var ready = false
    private var sending = false
    private var pending: Data?
    private var windowStart = ProcessInfo.processInfo.systemUptime
    private var windowCount = 0

    init(connection: NWConnection) { self.connection = connection }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, !self.closed else { return }
            switch state {
            case .ready:
                self.ready = true
                self.onReady?()
                if !self.closed { self.receive() }
            case .failed, .cancelled: self.cancel()
            default: break
            }
        }
        connection.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, !self.ready else { return }
            self.cancel()
        }
    }

    private func receive() {
        guard !closed else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, end, error in
            guard let self, !self.closed else { return }
            if let data, !data.isEmpty {
                do {
                    let now = ProcessInfo.processInfo.systemUptime
                    if now - self.windowStart >= 1 { self.windowStart = now; self.windowCount = 0 }
                    for packet in try self.decoder.ingest(data) {
                        self.windowCount += 1
                        guard self.windowCount <= 30 else { self.cancel(); return }
                        self.onPacket?(packet)
                        if self.closed { return }
                    }
                } catch { self.cancel(); return }
            }
            if end || error != nil { self.cancel() } else { self.receive() }
        }
    }

    func send(_ packet: MotionPacket) {
        guard ready, !closed else { return }
        do {
            let data = try packet.framed()
            if sending { pending = data } else { sendData(data) }
        } catch { cancel() }
    }

    private func sendData(_ data: Data) {
        sending = true
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self, !self.closed else { return }
            self.sending = false
            if error != nil { self.cancel(); return }
            if let next = self.pending { self.pending = nil; self.sendData(next) }
        })
    }

    func cancel() {
        guard !closed else { return }
        closed = true
        pending = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
        onClose?()
        onReady = nil; onPacket = nil; onClose = nil
    }
}

final class LocalLink: ObservableObject {
    static let serviceType = "_stride._tcp"
    @Published private(set) var peers: [StridePeer] = []
    @Published private(set) var pairing: PairingCode?
    @Published private(set) var status = "尚未連線"
    @Published private(set) var connected = false
    var onPacket: ((MotionPacket) -> Void)?
    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?
    private var browser: NWBrowser?
    private var listener: NWListener?
    private var channels: [UUID: MotionChannel] = [:]
    private var active: MotionChannel?
    private var desiredPairing: PairingCode?
    private var watchdog: Timer?
    private var lastPacketAt = 0.0

    func browse() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .tcp)
        self.browser = browser
        status = "搜尋同一網路上的 Apple TV…"
        browser.browseResultsChangedHandler = { [weak self, weak browser] results, _ in
            guard let self, self.browser === browser else { return }
            self.peers = results.compactMap { result in
                guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                return StridePeer(name: name, endpoint: result.endpoint)
            }.sorted { $0.name < $1.name }
            self.connectIfDiscovered()
        }
        browser.stateUpdateHandler = { [weak self, weak browser] state in
            guard let self, self.browser === browser else { return }
            if case .failed = state { self.status = "區域網路搜尋失敗；請檢查網路權限" }
        }
        browser.start(queue: .main)
    }

    func connect(pairing: PairingCode) {
        disconnect()
        desiredPairing = pairing
        browse()
        status = "等待指定的 Apple TV…"
        connectIfDiscovered()
    }

    private func connectIfDiscovered() {
        guard active == nil, channels.isEmpty, let code = desiredPairing,
              let peer = peers.first(where: { $0.name == code.service }) else { return }
        desiredPairing = nil // failed auth requires explicit rescan/retry, not an infinite loop
        let channel = MotionChannel(connection: NWConnection(to: peer.endpoint, using: StrideTLS.parameters(for: code)))
        channels[channel.id] = channel
        status = "驗證配對…"
        channel.onReady = { [weak self, weak channel] in
            guard let self, let channel, self.channels[channel.id] != nil else { return }
            self.active = channel; self.connected = true; self.status = "已安全連線"
            self.onConnected?()
        }
        channel.onClose = { [weak self, weak channel] in
            guard let self, let channel else { return }
            self.closed(channel)
        }
        channel.start()
    }

    func startServer() {
        stop()
        do {
            let code = try StrideTLS.newPairing()
            let listener = try NWListener(using: StrideTLS.parameters(for: code))
            pairing = code
            self.listener = listener
            listener.service = NWListener.Service(name: code.service, type: Self.serviceType)
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self, self.listener === listener else { return }
                switch state {
                case .ready: self.status = "等待 iPhone 配對"
                case .failed: self.status = "無法啟動區域網路服務"; self.disconnect()
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self, weak listener] connection in
                guard let self, self.listener === listener, self.channels.count < 4 else {
                    connection.cancel(); return
                }
                let channel = MotionChannel(connection: connection)
                self.channels[channel.id] = channel
                channel.onReady = { [weak self, weak channel] in
                    guard let self, let channel else { return }
                    guard self.active == nil else { channel.cancel(); return }
                    self.active = channel
                    self.lastPacketAt = ProcessInfo.processInfo.systemUptime
                    self.connected = true; self.status = "iPhone 已連線"
                    self.onConnected?()
                }
                channel.onPacket = { [weak self, weak channel] packet in
                    guard let self, let channel, self.active === channel else { return }
                    self.lastPacketAt = ProcessInfo.processInfo.systemUptime
                    self.onPacket?(packet)
                }
                channel.onClose = { [weak self, weak channel] in
                    guard let self, let channel else { return }
                    self.closed(channel)
                }
                channel.start()
            }
            listener.start(queue: .main)
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self, self.active != nil else { return }
                if ProcessInfo.processInfo.systemUptime - self.lastPacketAt > 3 { self.disconnect() }
            }
            watchdog = timer
            RunLoop.main.add(timer, forMode: .common)
        } catch { status = "無法建立安全配對" }
    }

    func send(_ packet: MotionPacket) { active?.send(packet) }

    private func closed(_ channel: MotionChannel) {
        let wasActive = active === channel
        channels.removeValue(forKey: channel.id)
        if wasActive { active = nil; connected = false; onDisconnected?() }
        if channels.isEmpty && active == nil {
            status = listener == nil ? "連線中斷或配對失敗；請重新連線" : "等待 iPhone 重新配對"
        }
    }

    func disconnect() {
        desiredPairing = nil
        let previous = Array(channels.values)
        for channel in previous { channel.cancel() }
        channels.removeAll()
        active = nil; connected = false
    }

    func stop() {
        watchdog?.invalidate(); watchdog = nil
        browser?.cancel(); browser = nil; peers = []
        listener?.cancel(); listener = nil; pairing = nil
        disconnect()
        status = "已停止"
    }
}
