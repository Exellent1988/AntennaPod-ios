// swift-tools-version:5.9
// Pure-Swift podcast rules (episode filters, listening-time accounting). No UIKit/AVFoundation,
// so the logic builds and tests on Linux (`swift test`).
import PackageDescription

let package = Package(
    name: "PodcastCore",
    platforms: [.iOS(.v17), .macOS(.v13), .watchOS(.v10)],
    products: [.library(name: "PodcastCore", targets: ["PodcastCore"])],
    targets: [
        .target(name: "PodcastCore"),
        .testTarget(name: "PodcastCoreTests", dependencies: ["PodcastCore"]),
    ]
)
