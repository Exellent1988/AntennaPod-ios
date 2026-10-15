import PodcastCore
import XCTest
@testable import AntennaPod

/// Android prefPlaybackSpeedArray on the real AppSettings / PlaybackService.
@MainActor
final class SpeedPresetsEditorTests: PlaybackFixtureTestCase {
    func testAddRemovePersistsSortedAndAndroidJSON() {
        settings.speedPresets = [1.0, 1.25, 1.5]
        XCTAssertTrue(settings.addSpeedPreset(0.9))
        XCTAssertFalse(settings.addSpeedPreset(1.25), "preset already exists")
        XCTAssertEqual(settings.speedPresets, [0.9, 1.0, 1.25, 1.5])
        XCTAssertEqual(UserDefaults.standard.string(forKey: SpeedPresets.defaultsKey), #"["0.90","1.00","1.25","1.50"]"#)
        XCTAssertTrue(settings.removeSpeedPreset(1.0))
        XCTAssertEqual(AppSettings().speedPresets, [0.9, 1.25, 1.5], "persisted")
        settings.speedPresets = [1.5]
        XCTAssertFalse(settings.removeSpeedPreset(1.5), "last preset stays")
        settings.speedPresets = []
        XCTAssertEqual(settings.speedPresets, [1.5], "empty list rejected")
        settings.speedPresets = [2, 1, 1]
        XCTAssertEqual(settings.speedPresets, [1, 2], "sorted, no duplicates")
        settings.resetSpeedPresetsToAndroidDefault()
        XCTAssertEqual(settings.speedPresets, [1.0, 1.25, 1.5])
    }

    func testBackupRoundTripAndOlderBackupKeepsPresets() throws {
        settings.speedPresets = [0.75, 1.4, 2.5]
        var snap = settings.backupSnapshot()
        XCTAssertEqual(snap.playbackSpeedPresets, [0.75, 1.4, 2.5])
        let decoded = try JSONDecoder().decode(AppSettingsBackupSnapshot.self, from: JSONEncoder().encode(snap))
        settings.speedPresets = [1.0]
        settings.applyBackupSnapshot(decoded)
        XCTAssertEqual(settings.speedPresets, [0.75, 1.4, 2.5])
        snap.playbackSpeedPresets = nil
        settings.speedPresets = [1.1, 1.3]
        settings.applyBackupSnapshot(snap)
        XCTAssertEqual(settings.speedPresets, [1.1, 1.3], "older backup without presets leaves them alone")
    }

    func testTapCyclesThroughEditedPresets() async throws {
        settings.speedPresets = [1.0, 1.6]
        XCTAssertTrue(playback.play(episode: episodes[0]))
        try await waitFor("playing", timeout: 5) { self.playback.isPlaying }
        playback.setRate(1.0)
        playback.cycleToNextSpeedPreset()
        XCTAssertEqual(playback.rate, 1.6, accuracy: 0.001)
        playback.cycleToNextSpeedPreset()
        XCTAssertEqual(playback.rate, 1.0, accuracy: 0.001, "wraps")
        playback.setRate(1.3)
        playback.cycleToNextSpeedPreset()
        XCTAssertEqual(playback.rate, 1.6, accuracy: 0.001, "between presets → next higher")
    }
}
