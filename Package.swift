// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StrideCore",
    platforms: [.iOS(.v17), .tvOS(.v17), .macOS(.v13)],
    products: [.library(name: "StrideCore", targets: ["StrideCore"])],
    targets: [
        .target(name: "StrideCore"),
        .testTarget(name: "StrideCoreTests", dependencies: ["StrideCore"])
    ]
)
