// swift-tools-version:5.9
// Linux-only harness: compiles the REAL CarPlay pure-logic files (symlinked from the app) against
// minimal STUBS of the app's store/model types (Sources/CarPlayLogic/Stubs.swift). Not shipped.
// Depends on the real PodcastCore package (FeedURLEquality = app FeedURLKey.key).
import PackageDescription
let package = Package(
    name: "CarPlayLinuxTests",
    dependencies: [.package(path: "../PodcastCore")],
    targets: [
        .target(name: "CarPlayLogic", dependencies: [.product(name: "PodcastCore", package: "PodcastCore")]),
        .testTarget(name: "CarPlayLogicTests", dependencies: ["CarPlayLogic", .product(name: "PodcastCore", package: "PodcastCore")]),
    ]
)
