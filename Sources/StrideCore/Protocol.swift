import Foundation

public enum StrideError: Error, Equatable {
    case invalidPacket, oversizedFrame, invalidPairingCode, invalidRoute
}

public struct MotionPacket: Codable, Equatable, Sendable {
    public let version: Int
    public let session: UUID
    public let sequence: UInt64
    public let cadence: Double
    public let confidence: Double
    public let steps: UInt64
    public let moving: Bool

    public init(session: UUID, sequence: UInt64, estimate: MotionEstimate) {
        version = 1
        self.session = session
        self.sequence = sequence
        cadence = estimate.cadence
        confidence = estimate.confidence
        steps = estimate.steps
        moving = estimate.isMoving
    }

    public func validate() throws {
        guard version == 1, cadence.isFinite, (0...240).contains(cadence),
              confidence.isFinite, (0...1).contains(confidence),
              steps <= 1_000_000_000,
              moving ? (cadence >= 30 && confidence >= 0.6) : cadence == 0 else {
            throw StrideError.invalidPacket
        }
    }

    public func framed() throws -> Data {
        try validate()
        var data = try JSONEncoder().encode(self)
        guard data.count <= FrameDecoder.limit else { throw StrideError.oversizedFrame }
        data.append(0x0A)
        return data
    }
}

/// Bounded newline-delimited JSON over an authenticated TLS stream. Chunk boundaries
/// have no relationship to packet boundaries. A malformed frame closes the connection.
public struct FrameDecoder: Sendable {
    public static let limit = 4096
    private var partial = Data()
    public init() {}

    public mutating func ingest(_ data: Data) throws -> [MotionPacket] {
        guard data.count <= 16_384 else { throw StrideError.oversizedFrame }
        var packets: [MotionPacket] = []
        for byte in data {
            if byte == 0x0A {
                guard !partial.isEmpty, packets.count < 64 else { throw StrideError.invalidPacket }
                let packet = try JSONDecoder().decode(MotionPacket.self, from: partial)
                try packet.validate()
                packets.append(packet)
                partial.removeAll(keepingCapacity: true)
            } else {
                guard partial.count < Self.limit else { throw StrideError.oversizedFrame }
                partial.append(byte)
            }
        }
        return packets
    }
}

/// The random 128-bit secret is exchanged out of band (QR / manual entry), never Bonjour.
public struct PairingCode: Equatable, Sendable {
    public let service: String
    public let key: String

    public init(service: String, key: String) throws {
        let normalized = key.lowercased()
        guard service.hasPrefix("Stride-"), (8...64).contains(service.utf8.count),
              service.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) ||
                  (97...122).contains($0) || $0 == 45 }),
              normalized.utf8.count == 32,
              normalized.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw StrideError.invalidPairingCode
        }
        self.service = service
        self.key = normalized
    }

    public init(url: String) throws {
        guard url.utf8.count < 256, let components = URLComponents(string: url),
              components.scheme == "stride", components.host == "pair",
              components.path.isEmpty, components.user == nil, components.password == nil,
              components.port == nil, components.fragment == nil,
              let items = components.queryItems, items.count == 2,
              items.filter({ $0.name == "service" }).count == 1,
              items.filter({ $0.name == "key" }).count == 1,
              let service = items.first(where: { $0.name == "service" })?.value,
              let key = items.first(where: { $0.name == "key" })?.value else {
            throw StrideError.invalidPairingCode
        }
        try self.init(service: service, key: key)
    }

    public var url: String {
        var components = URLComponents()
        components.scheme = "stride"
        components.host = "pair"
        components.queryItems = [URLQueryItem(name: "service", value: service),
                                URLQueryItem(name: "key", value: key)]
        return components.string ?? ""
    }

    public var secret: Data {
        var result = Data()
        var index = key.startIndex
        while index < key.endIndex {
            let next = key.index(index, offsetBy: 2)
            result.append(UInt8(key[index..<next], radix: 16)!) // validated at initialization
            index = next
        }
        return result
    }
}
