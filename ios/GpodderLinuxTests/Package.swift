// swift-tools-version:5.9
// Linux harness (not in any Xcode target): compiles the app's real gpodder episode-action
// logic (GpodderSyncLogic.swift, GpodderActionQueue.swift via symlinks) against real
// PodcastCore, with marked stubs for the app types they reference.
import PackageDescription
let package = Package(
    name: "GpodderLinuxTests",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../PodcastCore")],
    targets: [
        .target(name: "GpodderLogic", dependencies: ["PodcastCore"]),
        .testTarget(name: "GpodderLogicTests", dependencies: ["GpodderLogic", "PodcastCore"]),
    ]
)
