import XCTest
@testable import AntennaPod

/// PlaybackService entry points (play, skipToNextEpisode, seek, pause)
/// write the PodcastStore state that gpodder sync turns into `play` actions.
/// Expected values follow Android SynchronizationQueueImpl.enqueueEpisodePlayed.
@MainActor
final class GpodderPlayActionTests: PlaybackFixtureTestCase {
    override func setUp() async throws {
        try await super.setUp()
        settings.keepSkippedEpisodes = true   // Android default: skips are kept (unplayed, real position)
    }

    private func action(for episode: PodcastEpisode) -> GpodderEpisodeAction? {
        let refs = episodes.map {
            GpodderSyncLogic.EpisodeRef(episodeId: $0.id, feedUrl: "https://example.com/feed",
                                        mediaUrl: "https://example.com/\($0.id).mp3")
        }
        return GpodderSyncLogic.localActions(refs: refs, localStates: store.playbackStates,
                                             sinceMs: 0, deviceId: "ios_test")
            .first { $0.guid == episode.id }
    }

    private func playAndWait(_ episode: PodcastEpisode, past seconds: Double) async throws {
        XCTAssertTrue(playback.play(episode: episode))
        try await waitFor("position > \(seconds)", timeout: 5) { self.playback.positionSeconds > seconds }
    }

    func testPlayThenSkipEpisodeRecordsRealPositionBeforeSmartMarkWindow() async throws {
        settings.smartMarkAsPlayedSeconds = 0
        try await playAndWait(episodes[0], past: 1.0)
        let at = playback.positionSeconds
        playback.skipToNextEpisode()
        XCTAssertFalse(store.isPlayed(episodes[0].id), "Kept skip stays unplayed")
        let a = try XCTUnwrap(action(for: episodes[0]))
        XCTAssertEqual(a.action, "play")
        XCTAssertEqual(a.started, 0)
        XCTAssertEqual(a.total, 3)
        XCTAssertEqual(Double(a.position ?? -1), at, accuracy: 1.0, "Android: skipped, not completed → real position")
        XCTAssertLessThan(a.position ?? 99, 3)
        XCTAssertEqual(playback.currentEpisode?.id, episodes[1].id)
    }

    func testSkipInsideSmartMarkWindowRecordsCompleted() async throws {
        settings.smartMarkAsPlayedSeconds = 10   // whole 3 s fixture is "almost ended"
        try await playAndWait(episodes[0], past: 0.6)
        playback.skipToNextEpisode()
        let a = try XCTUnwrap(action(for: episodes[0]))
        XCTAssertEqual(a.position, 3, "Android: ended || almostEnded → position = total")
        XCTAssertEqual(a.total, 3)
    }

    func testSeekThenPauseRecordsPausePositionAndSessionStart() async throws {
        settings.smartMarkAsPlayedSeconds = 0
        try await playAndWait(episodes[0], past: 0.6)
        playback.togglePlayPause()   // pause
        let resumeFrom = playback.positionSeconds
        playback.togglePlayPause()            // new session: started = resume point
        XCTAssertTrue(playback.isPlaying)
        playback.seek(toSeconds: 2.0)
        playback.togglePlayPause()   // pause
        let a = try XCTUnwrap(action(for: episodes[0]))
        XCTAssertEqual(Double(a.started ?? -1), resumeFrom, accuracy: 0.6)
        XCTAssertEqual(Double(a.position ?? -1), 2.0, accuracy: 0.6)
        XCTAssertEqual(a.total, 3)
        XCTAssertFalse(store.playbackState(for: episodes[0].id).isPlayed)
    }

    func testNoProgressSessionIsNotUploaded() {
        var s = EpisodePlaybackState(positionSeconds: 40, durationSeconds: 100, isPlayed: false, updatedAtEpochMs: 5000)
        s.playStartedSeconds = 40
        let refs = [GpodderSyncLogic.EpisodeRef(episodeId: "x", feedUrl: "https://e/f", mediaUrl: "https://e/x.mp3")]
        XCTAssertTrue(GpodderSyncLogic.localActions(refs: refs, localStates: ["x": s], sinceMs: 0, deviceId: "d").isEmpty)
        s.positionSeconds = 55
        let a = GpodderSyncLogic.localActions(refs: refs, localStates: ["x": s], sinceMs: 0, deviceId: "d").first
        XCTAssertEqual(a?.started, 40); XCTAssertEqual(a?.position, 55)
    }
}
