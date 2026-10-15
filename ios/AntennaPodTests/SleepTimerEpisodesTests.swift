import PodcastCore
import XCTest
@testable import AntennaPod

/// Android `SleepTimerType.EPISODES`: stop after N episodes, extend +N, shake reset,
/// remembered type / count, auto-enable, backup.
@MainActor
final class SleepTimerEpisodesTests: XCTestCase {
    private var settings: AppSettings!
    private var original: AppSettingsBackupSnapshot!
    private var playback: PlaybackService!

    override func setUp() async throws {
        settings = AppSettings()
        original = settings.backupSnapshot()
        playback = PlaybackService()
        playback.settings = settings
    }

    override func tearDown() async throws {
        playback.disableSleepTimer()
        settings.applyBackupSnapshot(original)
    }

    func testStartingRemembersCountAndType() {
        playback.setSleepTimer(episodes: 3)
        XCTAssertEqual(playback.sleepTimerMode, .episodes)
        XCTAssertTrue(playback.isSleepTimerActive)
        XCTAssertEqual(playback.sleepTimerEpisodeCounter?.remaining, 3)
        XCTAssertEqual(settings.lastSleepTimerEpisodes, 3)
        XCTAssertEqual(settings.sleepTimerKind, .episodes)
        XCTAssertNil(playback.sleepTimerRemainingSeconds, "No clock countdown")
        playback.setSleepTimer(minutes: 10)
        XCTAssertEqual(settings.sleepTimerKind, .clock)
        XCTAssertNil(playback.sleepTimerEpisodeCounter)
    }

    func testEachFinishedEpisodeCountsAndTheLastStops() {
        playback.setSleepTimer(episodes: 3)
        XCTAssertTrue(playback.recordSleepTimerEpisodeFinished())
        XCTAssertTrue(playback.recordSleepTimerEpisodeFinished())
        XCTAssertEqual(playback.sleepTimerEpisodeCounter?.remaining, 1)
        XCTAssertEqual(playback.sleepTimerStatusLabel, String(localized: "\(1) ep."))
        XCTAssertFalse(playback.recordSleepTimerEpisodeFinished(), "Third episode end stops playback")
    }

    func testOtherModesAreNotCounted() {
        playback.setSleepTimer(minutes: 5)
        XCTAssertTrue(playback.recordSleepTimerEpisodeFinished())
        XCTAssertEqual(playback.sleepTimerMode, .clock(minutes: 5))
    }

    func testExtendAddsEpisodesAndShakeResets() {
        playback.setSleepTimer(episodes: 2)
        playback.recordSleepTimerEpisodeFinished()
        playback.extendSleepTimer(byEpisodes: 3)
        XCTAssertEqual(playback.sleepTimerEpisodeCounter?.remaining, 4)
        playback.resetSleepTimerToInitial()
        XCTAssertEqual(playback.sleepTimerEpisodeCounter?.remaining, 2)
        XCTAssertEqual(settings.lastSleepTimerEpisodes, 2, "Extend does not change the remembered value")
    }

    func testExtendOnOtherModeStartsEpisodeTimerAndMinutesExtendSwitchesToClock() {
        playback.setSleepTimerEndOfEpisode()
        playback.extendSleepTimer(byEpisodes: 2)
        XCTAssertEqual(playback.sleepTimerMode, .episodes)
        XCTAssertEqual(playback.sleepTimerEpisodeCounter?.remaining, 2)
        playback.extendSleepTimer(byMinutes: 5)
        XCTAssertEqual(playback.sleepTimerMode, .clock(minutes: 5))
        XCTAssertNil(playback.sleepTimerEpisodeCounter)
    }

    func testManualSkipWithoutEpisodeIsNoOp() {
        playback.setSleepTimer(episodes: 2)
        playback.skipToNextEpisode()
        XCTAssertEqual(playback.sleepTimerEpisodeCounter?.remaining, 2)
    }

    func testAutoEnableStartsEpisodeTimerWhenThatWasLastUsed() {
        settings.sleepTimerAutoEnable = true
        settings.sleepTimerAutoEnableFromHour = 0
        settings.sleepTimerAutoEnableToHour = 0
        settings.lastSleepTimerEpisodes = 4
        settings.sleepTimerKind = .episodes
        playback.autoEnableSleepTimerIfNeeded()
        XCTAssertEqual(playback.sleepTimerMode, .episodes)
        XCTAssertEqual(playback.sleepTimerEpisodeCounter?.remaining, 4)
        XCTAssertTrue(playback.sleepTimerWasAutoEnabled)
    }

    func testBackupRoundTripDefaultsAndClamp() throws {
        settings.lastSleepTimerEpisodes = 5
        settings.sleepTimerKind = .episodes
        let data = try JSONEncoder().encode(settings.backupSnapshot())
        var snap = try JSONDecoder().decode(AppSettingsBackupSnapshot.self, from: data)
        XCTAssertEqual(snap.lastSleepTimerEpisodes, 5)
        XCTAssertEqual(snap.sleepTimerKind, "episodes")
        settings.lastSleepTimerEpisodes = 1
        settings.sleepTimerKind = .clock
        settings.applyBackupSnapshot(snap)
        XCTAssertEqual(settings.lastSleepTimerEpisodes, 5)
        XCTAssertEqual(settings.sleepTimerKind, .episodes)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "settings.lastSleepTimerEpisodes"), 5)
        XCTAssertEqual(AppSettings().sleepTimerKind, .episodes, "Persists in UserDefaults")

        snap.lastSleepTimerEpisodes = nil
        snap.sleepTimerKind = nil
        settings.applyBackupSnapshot(snap)
        XCTAssertEqual(settings.lastSleepTimerEpisodes, 1, "Android default LastValue episodes = 1")
        XCTAssertEqual(settings.sleepTimerKind, .clock)

        snap.lastSleepTimerEpisodes = 500
        snap.sleepTimerKind = "bogus"
        settings.applyBackupSnapshot(snap)
        XCTAssertEqual(settings.lastSleepTimerEpisodes, EpisodeSleepCounter.range.upperBound)
        XCTAssertEqual(settings.sleepTimerKind, .clock)
    }
}
