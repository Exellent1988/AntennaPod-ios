import AVFoundation
import Foundation

/// Test hygiene: when the app runs as the XCTest host, playback must make no sound and must not
/// take over the Mac's audio (the simulator plays through the Mac). Players are created muted
/// (`isMuted`, so `volume`-based logic such as the sleep fade stays testable) and the shared
/// `AVAudioSession` is never configured or activated; the calls are recorded instead.
enum TestHostAudio {
    /// True inside an XCTest host process (unit tests), never in a normal app launch.
    static let isActive: Bool = {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil
            || env["XCTestSessionIdentifier"] != nil || NSClassFromString("XCTestCase") != nil
    }()

    /// Fake session log for tests (activate / deactivate / preferred channels).
    @MainActor static var activatedModes: [AVAudioSession.Mode] = []
    @MainActor static var deactivationCount = 0
    @MainActor static var preferredChannelRequests = 0
}
