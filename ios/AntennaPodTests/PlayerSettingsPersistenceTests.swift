import AudioDSP
import PodcastCore
import XCTest
@testable import AntennaPod

/// Axel's device test (build a9539a179): after a crash the player speed was back at the default.
/// Root cause: the player's session speed (`PlaybackService.setRate`) lived only in memory.
/// These tests simulate a kill: no `stop()`, no willTerminate, no background notification —
/// the in-memory objects are simply dropped and fresh ones are built from storage.
@MainActor
final class PlayerSettingsPersistenceTests: PlaybackFixtureTestCase {

    /// Drops the in-memory store / player / settings without any shutdown hook and builds new ones.
    private func simulateKillAndRelaunch() {
        playback.togglePlayPause() // only silence the old AVPlayer; not a shutdown hook
        settings = AppSettings()
        store = PodcastStore()
        store.settings = settings
        store.queue = episodes
        playback = PlaybackService()
        playback.settings = settings
        playback.store = store
        store.playback = playback
    }

    func testSessionSpeedSurvivesKillWithoutShutdownHooks() async throws {
        settings.defaultPlaybackSpeed = 1.0
        let ep = episodes[0]
        XCTAssertTrue(playback.play(episode: ep))
        try await waitFor("playing", timeout: 5) { self.playback.isPlaying }
        playback.setRate(1.75)

        simulateKillAndRelaunch()
        XCTAssertEqual(settings.defaultPlaybackSpeed, 1.0, "session speed must not leak into the global default")
        playback.restoreLastEpisodeIfPossible()
        XCTAssertEqual(playback.restoredEpisode?.id, ep.id)
        XCTAssertEqual(playback.rate, 1.75, accuracy: 0.001, "restored placeholder shows the saved speed")
        XCTAssertTrue(playback.playRestoredEpisode())
        XCTAssertEqual(playback.rate, 1.75, accuracy: 0.001, "Play after relaunch keeps the saved speed")
    }

    func testSessionSpeedDoesNotCarryToAnotherEpisode() async throws {
        settings.defaultPlaybackSpeed = 1.25
        XCTAssertTrue(playback.play(episode: episodes[0]))
        playback.setRate(2.0)
        simulateKillAndRelaunch()
        XCTAssertTrue(playback.play(episode: episodes[1]))
        XCTAssertEqual(playback.rate, 1.25, accuracy: 0.001)
        XCTAssertNil(SessionPlaybackSpeed.load(), "a different episode drops the old session speed")
    }

    func testStopClearsSessionSpeed() {
        XCTAssertTrue(playback.play(episode: episodes[0]))
        playback.setRate(1.5)
        XCTAssertEqual(SessionPlaybackSpeed.load(), SessionPlaybackSpeed(episodeId: episodes[0].id, speed: 1.5))
        playback.stop()
        XCTAssertNil(SessionPlaybackSpeed.load())
    }

    func testGlobalPlayerPrefsSurviveKill() {
        settings.defaultPlaybackSpeed = 1.6
        settings.skipSilenceEnabled = !settings.skipSilenceEnabled
        let skip = settings.skipSilenceEnabled
        let nextMode = VolumeAdaptationMode.allCases.first { $0 != settings.volumeAdaptationMode }!
        settings.volumeAdaptationMode = nextMode
        settings.lastSleepTimerMinutes = 37
        settings.sleepTimerFadeEnabled = !settings.sleepTimerFadeEnabled
        let fade = settings.sleepTimerFadeEnabled

        simulateKillAndRelaunch()
        XCTAssertEqual(settings.defaultPlaybackSpeed, 1.6, accuracy: 0.001)
        XCTAssertEqual(settings.skipSilenceEnabled, skip)
        XCTAssertEqual(settings.volumeAdaptationMode, nextMode)
        XCTAssertEqual(settings.lastSleepTimerMinutes, 37)
        XCTAssertEqual(settings.sleepTimerFadeEnabled, fade)
    }

    func testFeedOverrideAndGlobalStayIndependentAcrossKill() {
        let feedId = UUID()
        defer { store.setFeedSettings(.default, for: feedId) }
        settings.defaultPlaybackSpeed = 1.2
        store.updateFeedSettings(for: feedId) { $0.playbackSpeed = 2.0 }
        XCTAssertEqual(settings.defaultPlaybackSpeed, 1.2, accuracy: 0.001, "feed override must not change global")

        simulateKillAndRelaunch()
        XCTAssertEqual(store.feedSettings(for: feedId).playbackSpeed, 2.0)
        XCTAssertEqual(settings.defaultPlaybackSpeed, 1.2, accuracy: 0.001)

        settings.defaultPlaybackSpeed = 0.9
        XCTAssertEqual(store.feedSettings(for: feedId).playbackSpeed, 2.0, "global must not change feed override")
        simulateKillAndRelaunch()
        XCTAssertEqual(store.feedSettings(for: feedId).playbackSpeed, 2.0)
        XCTAssertEqual(settings.defaultPlaybackSpeed, 0.9, accuracy: 0.001)
        XCTAssertEqual(store.feedSettings(for: feedId).resolvedPlaybackSpeed(global: settings.defaultPlaybackSpeed), 2.0)
    }

    func testSessionSpeedNeverWritesGlobalOrFeed() {
        settings.defaultPlaybackSpeed = 1.0
        XCTAssertTrue(playback.play(episode: episodes[0]))
        playback.setRate(2.5)
        XCTAssertEqual(AppSettings().defaultPlaybackSpeed, 1.0, accuracy: 0.001)
        XCTAssertEqual(UserDefaults.standard.float(forKey: SessionPlaybackSpeed.speedKey), 2.5, accuracy: 0.001)
    }
}
