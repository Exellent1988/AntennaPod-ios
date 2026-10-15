import PodcastCore
import XCTest
@testable import AntennaPod

/// Android `prefSkipKeepsEpisode` with real playback: a kept skip saves the position, keeps the
/// episode unplayed in the queue, still advances, counts for the episode sleep timer, and the
/// gpodder action carries the real position (not played).
@MainActor
final class KeepSkippedEpisodesTests: PlaybackFixtureTestCase {
    override func setUp() async throws {
        try await super.setUp()
        settings.keepSkippedEpisodes = true   // Android default
        // 3 s fixtures sit inside the default 30 s Smart mark window; turn it off so a skip is a real skip.
        settings.smartMarkAsPlayedSeconds = 0
    }

    func testDefaultAndBackup() throws {
        var old = settings.backupSnapshot()
        old.keepSkippedEpisodes = nil
        settings.applyBackupSnapshot(old)
        XCTAssertTrue(settings.keepSkippedEpisodes, "Android default on")
        settings.keepSkippedEpisodes = false
        let snap = try JSONDecoder().decode(AppSettingsBackupSnapshot.self, from: JSONEncoder().encode(settings.backupSnapshot()))
        settings.keepSkippedEpisodes = true
        settings.applyBackupSnapshot(snap)
        XCTAssertFalse(settings.keepSkippedEpisodes)
    }

    func testFeedOverrideResolutionAndCodable() throws {
        var fs = FeedSettings.default
        XCTAssertTrue(fs.resolvedKeepSkippedEpisodes(global: true))
        fs.keepSkippedEpisodes = .never
        XCTAssertFalse(fs.resolvedKeepSkippedEpisodes(global: true))
        fs.keepSkippedEpisodes = .always
        XCTAssertTrue(fs.resolvedKeepSkippedEpisodes(global: false))
        let decoded = try JSONDecoder().decode(FeedSettings.self, from: JSONEncoder().encode(fs))
        XCTAssertEqual(decoded.keepSkippedEpisodes, .always)
        let legacy = try JSONDecoder().decode(FeedSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(legacy.keepSkippedEpisodes, .useGlobal, "Older feed-settings.json")
    }

    func testKeptSkipAdvancesButKeepsEpisodeUnplayedInQueue() async throws {
        XCTAssertTrue(playback.play(episode: episodes[0]))
        try await waitFor("past 1 s", timeout: 8) { self.playback.positionSeconds > 1 }
        playback.skipToNextEpisode()
        XCTAssertEqual(playback.currentEpisode?.id, episodes[1].id, "Still advances")
        let state = store.playbackState(for: episodes[0].id)
        XCTAssertFalse(state.isPlayed)
        XCTAssertGreaterThan(state.positionSeconds, 0.9, "Position saved for resume")
        XCTAssertTrue(store.queue.contains { $0.id == episodes[0].id }, "Stays in the queue")

        // gpodder: a play action with the real position, not position == total.
        let refs = [GpodderSyncLogic.EpisodeRef(episodeId: episodes[0].id, feedUrl: "https://example.invalid/feed.xml",
                                                mediaUrl: "https://example.invalid/a.mp3")]
        let action = try XCTUnwrap(GpodderSyncLogic.localActions(refs: refs, localStates: store.playbackStates,
                                                                 sinceMs: 0, deviceId: "t").first)
        XCTAssertEqual(action.action, "play")
        XCTAssertEqual(action.total, 3)
        XCTAssertLessThan(action.position ?? 3, 3)
        XCTAssertGreaterThanOrEqual(action.position ?? 0, 1)
    }

    func testKeptSkipStillCountsForEpisodeSleepTimer() async throws {
        XCTAssertTrue(playback.play(episode: episodes[0]))
        playback.setSleepTimer(episodes: 2, remember: false)
        try await waitFor("past 1 s", timeout: 8) { self.playback.positionSeconds > 1 }
        playback.skipToNextEpisode()
        XCTAssertEqual(playback.sleepTimerEpisodeCounter?.remaining, 1)
        XCTAssertFalse(store.isPlayed(episodes[0].id))
    }

    func testKeptSkipInsideSmartMarkWindowIsStillPlayed() async throws {
        settings.smartMarkAsPlayedSeconds = 30
        XCTAssertTrue(playback.play(episode: episodes[0]))
        try await waitFor("past 1 s", timeout: 8) { self.playback.positionSeconds > 1 }
        playback.skipToNextEpisode()
        XCTAssertTrue(store.isPlayed(episodes[0].id), "Android: skipped && almostEnded → played")
    }

    func testOffMarksPlayedAndHardwareSkipFollowsTheSetting() async throws {
        settings.keepSkippedEpisodes = false
        XCTAssertTrue(playback.play(episode: episodes[0]))
        try await waitFor("past 1 s", timeout: 8) { self.playback.positionSeconds > 1 }
        playback.performHardwareButton(.skipEpisode)
        XCTAssertTrue(store.isPlayed(episodes[0].id))
        XCTAssertFalse(store.queue.contains { $0.id == episodes[0].id })
    }

    func testNaturalEndAndSkipEndingIgnoreTheSetting() async throws {
        settings.skipOutroSeconds = 1
        XCTAssertTrue(playback.play(episode: episodes[0]))
        try await waitFor("episode 2 via Skip ending", timeout: 12) { self.playback.currentEpisode?.id == self.episodes[1].id }
        settings.skipOutroSeconds = 0
        try await waitFor("episode 3 via natural end", timeout: 12) { self.playback.currentEpisode?.id == self.episodes[2].id }
        assertFinished(episodes[0])
        assertFinished(episodes[1])
    }
}
