import Foundation

public struct RoutePoint: Codable, Equatable, Sendable {
    public let x: Double
    public let z: Double
    public init(x: Double, z: Double) { self.x = x; self.z = z }
}

public struct RoutePose: Equatable, Sendable {
    public let point: RoutePoint
    public let yaw: Double
}

/// Local-metre polyline. No dependency on any commercial map or imagery provider.
public struct Route: Sendable {
    public let points: [RoutePoint]
    public let length: Double
    private let cumulative: [Double]

    public init(points: [RoutePoint]) throws {
        guard (2...100_000).contains(points.count), points.allSatisfy({
            $0.x.isFinite && $0.z.isFinite && abs($0.x) <= 1e7 && abs($0.z) <= 1e7
        }) else { throw StrideError.invalidRoute }
        var cumulative = [0.0]
        for i in 1..<points.count {
            let distance = hypot(points[i].x - points[i - 1].x, points[i].z - points[i - 1].z)
            guard distance > 0.0001 else { throw StrideError.invalidRoute }
            cumulative.append(cumulative.last! + distance)
        }
        self.points = points
        self.cumulative = cumulative
        length = cumulative.last!
    }

    public func pose(at distance: Double, looping: Bool = true) -> RoutePose {
        let safeDistance = distance.isFinite ? max(0, distance) : 0
        let d = looping ? safeDistance.truncatingRemainder(dividingBy: length) : min(length, safeDistance)
        var low = 0, high = cumulative.count - 1
        while low + 1 < high {
            let mid = (low + high) / 2
            if cumulative[mid] <= d { low = mid } else { high = mid }
        }
        let a = points[low], b = points[high]
        let t = (d - cumulative[low]) / (cumulative[high] - cumulative[low])
        return RoutePose(point: RoutePoint(x: a.x + (b.x - a.x) * t, z: a.z + (b.z - a.z) * t),
                         yaw: atan2(-(b.x - a.x), -(b.z - a.z)))
    }

    public static var demo: Route {
        // Original procedural loop, distributed under this repository's MIT license.
        let points = (0...192).map { i -> RoutePoint in
            let angle = Double(i) / 192 * 2 * Double.pi
            return RoutePoint(x: 80 * sin(angle), z: -80 * cos(angle))
        }
        return try! Route(points: points)
    }
}

public enum MediaPolicy {
    /// Only explicit, credential-free HTTPS media. No scraping, bundled proprietary
    /// imagery, ATS bypass, arbitrary local-file reads, or embedded API tokens.
    public static func videoURL(_ text: String) -> URL? {
        guard text.utf8.count <= 4096, let url = URL(string: text),
              url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.fragment == nil else { return nil }
        return url
    }

    public static func rate(speed: Double, recordedSpeed: Double) -> Float {
        guard speed.isFinite, speed > 0, recordedSpeed.isFinite, recordedSpeed > 0 else { return 0 }
        return Float(min(2, max(0.25, speed / recordedSpeed)))
    }
}
