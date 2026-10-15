// swift-tools-version:5.9
// Linux-only harness: compiles the REAL CarPlay pure-logic files (symlinked from the app) against
// minimal STUBS of the app's store/model types (Sources/CarPlayLogic/Stubs.swift). Not shipped.
import PackageDescription
let package = Package(
    name: "CarPlayLinuxTests",
    targets: [
        .target(name: "CarPlayLogic"),
        .testTarget(name: "CarPlayLogicTests", dependencies: ["CarPlayLogic"]),
    ]
)
