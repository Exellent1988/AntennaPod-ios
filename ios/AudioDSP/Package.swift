// swift-tools-version:5.9
// Pure-Swift audio DSP used by the iOS playback pipeline (MTAudioProcessingTap on AVPlayerItem).
// No AVFoundation imports here so the logic builds and tests on Linux (`swift test`).
import PackageDescription

let package = Package(
    name: "AudioDSP",
    platforms: [.iOS(.v17), .macOS(.v13), .watchOS(.v10)],
    products: [.library(name: "AudioDSP", targets: ["AudioDSP"])],
    targets: [
        .target(name: "AudioDSP"),
        .testTarget(name: "AudioDSPTests", dependencies: ["AudioDSP"]),
    ]
)
