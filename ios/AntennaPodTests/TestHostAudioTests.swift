import XCTest
@testable import AntennaPod

/// Unit tests play no sound and never touch the real audio session (beeps / interrupted music
/// on the Mac running the simulator).
@MainActor
final class TestHostAudioTests: PlaybackFixtureTestCase {
    func testTestHostIsDetected() {
        XCTAssertTrue(TestHostAudio.isActive)
    }

    func testPlaybackIsMutedAndUsesTheFakeSession() {
        let before = TestHostAudio.activatedModes.count
        XCTAssertTrue(playback.play(episode: episodes[0]))
        XCTAssertTrue(playback.isOutputMuted, "players are muted in the test host")
        XCTAssertGreaterThan(TestHostAudio.activatedModes.count, before, "activation recorded, real session untouched")
        playback.stop()
    }
}
