import AudioDSP
import PodcastCore
import XCTest
@testable import AntennaPod

/// Audit on combined f7cc344fd: every option the player UI and its sheets write must survive a
/// kill (no stop(), no willTerminate, no background notification). Complements
/// PlayerSettingsPersistenceTests (session speed, default speed, feed speed).
@MainActor
final class PlayerOptionsKillAuditTests: PlaybackFixtureTestCase {
    private func simulateKillAndRelaunch() {
        if playback.isPlaying { playback.togglePlayPause() }
        settings = AppSettings()
        store = PodcastStore()
        store.settings = settings
        store.queue = episodes
        retiredPlaybacks.append(playback)
        playback = PlaybackService()
        playback.settings = settings
        playback.store = store
        store.playback = playback
    }

    /// Full player bottom bar: Skip silence button (global) via PlaybackService.
    func testPlayerSkipSilenceButtonSurvivesKill() {
        let before = settings.skipSilenceEnabled
        playback.toggleSkipSilence()
        simulateKillAndRelaunch()
        XCTAssertEqual(settings.skipSilenceEnabled, !before)
    }

    /// Full player Volume adaptation menu (per podcast) and per-podcast Skip silence overrides.
    func testPerPodcastPlayerOverridesSurviveKill() {
        let feedId = UUID()
        defer { store.setFeedSettings(.default, for: feedId) }
        let mode = VolumeAdaptationMode.allCases.last!
        let level = SkipSilenceLevel.aggressive
        store.updateFeedSettings(for: feedId) {
            $0.volumeAdaptation = mode
            $0.skipSilence = true
            $0.skipSilenceLevel = level
            $0.playbackSpeed = 1.7
        }
        simulateKillAndRelaunch()
        let fs = store.feedSettings(for: feedId)
        XCTAssertEqual(fs.volumeAdaptation, mode)
        XCTAssertEqual(fs.skipSilence, true)
        XCTAssertEqual(fs.skipSilenceLevel, level)
        XCTAssertEqual(fs.playbackSpeed, 1.7)
    }

    /// Sleep timer sheet options and the last used timer.
    func testSleepTimerSheetPrefsSurviveKill() {
        settings.sleepTimerKind = .episodes
        settings.lastSleepTimerEpisodes = 4
        settings.lastSleepTimerMinutes = 23
        let shake = !settings.sleepTimerShakeToReset, vibrate = !settings.sleepTimerVibrate
        settings.sleepTimerShakeToReset = shake
        settings.sleepTimerVibrate = vibrate
        settings.sleepTimerAutoEnableFromHour = 21
        settings.sleepTimerAutoEnableToHour = 5
        simulateKillAndRelaunch()
        XCTAssertEqual(settings.sleepTimerKind, .episodes)
        XCTAssertEqual(settings.lastSleepTimerEpisodes, 4)
        XCTAssertEqual(settings.lastSleepTimerMinutes, 23)
        XCTAssertEqual(settings.sleepTimerShakeToReset, shake)
        XCTAssertEqual(settings.sleepTimerVibrate, vibrate)
        XCTAssertEqual(settings.sleepTimerAutoEnableFromHour, 21)
        XCTAssertEqual(settings.sleepTimerAutoEnableToHour, 5)
    }

    /// Other global options reachable from the player (skip intervals sheet, audio options,
    /// remaining-time tap, video as audio).
    func testOtherPlayerGlobalsSurviveKill() {
        settings.rewindSeconds = 17
        settings.fastForwardSeconds = 43
        let level: SkipSilenceLevel = settings.skipSilenceLevel == .aggressive ? .mild : .aggressive
        settings.skipSilenceLevel = level
        let mono = !settings.stereoToMonoEnabled, pitch = !settings.preservePitchEnabled
        settings.stereoToMonoEnabled = mono
        settings.preservePitchEnabled = pitch
        let remaining = !settings.showRemainingTime, audioOnly = !settings.playVideoAsAudioOnly
        settings.showRemainingTime = remaining
        settings.playVideoAsAudioOnly = audioOnly
        simulateKillAndRelaunch()
        XCTAssertEqual(settings.rewindSeconds, 17)
        XCTAssertEqual(settings.fastForwardSeconds, 43)
        XCTAssertEqual(settings.skipSilenceLevel, level)
        XCTAssertEqual(settings.stereoToMonoEnabled, mono)
        XCTAssertEqual(settings.preservePitchEnabled, pitch)
        XCTAssertEqual(settings.showRemainingTime, remaining)
        XCTAssertEqual(settings.playVideoAsAudioOnly, audioOnly)
    }
}
