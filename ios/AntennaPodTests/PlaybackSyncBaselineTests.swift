import XCTest
@testable import AntennaPod

/// Pre-change reference for gpodder-facing state, using only APIs that exist before the episode
/// sleep timer (runs unchanged on the base commit): natural end, Skip ending, pause mid-episode.
/// Values asserted here must not change with new finish paths.
@MainActor
final class PlaybackSyncBaselineTests: PlaybackFixtureTestCase {
    func testFinishedAndPausedStatesAndGpodderActions() async throws {
        settings.skipOutroSeconds = 1
        XCTAssertTrue(playback.play(episode: episodes[0]))          // ends via Skip ending
        try await waitFor("episode 2", timeout: 12) { self.playback.currentEpisode?.id == self.episodes[1].id }
        settings.skipOutroSeconds = 0
        try await waitFor("episode 3", timeout: 12) { self.playback.currentEpisode?.id == self.episodes[2].id }  // natural end
        try await waitFor("episode 3 past 1 s", timeout: 8) { self.playback.positionSeconds > 1 }
        playback.togglePlayPause()

        assertFinished(episodes[0])
        assertFinished(episodes[1])
        let paused = store.playbackState(for: episodes[2].id)
        XCTAssertFalse(paused.isPlayed)
        XCTAssertGreaterThan(paused.positionSeconds, 0.9)
        XCTAssertEqual(store.queue.map(\.id), [episodes[2].id], "Finished episodes left the queue")

        let refs = episodes.map {
            GpodderSyncLogic.EpisodeRef(episodeId: $0.id, feedUrl: "https://example.invalid/feed.xml",
                                        mediaUrl: "https://example.invalid/\($0.id).mp3")
        }
        let actions = GpodderSyncLogic.localActions(refs: refs, localStates: store.playbackStates,
                                                    sinceMs: 0, deviceId: "test")
        XCTAssertEqual(actions.count, 3)
        for action in actions {
            XCTAssertEqual(action.action, "play")
            XCTAssertEqual(action.started, 0)
            XCTAssertEqual(action.total, Int(Self.fixtureSeconds))
        }
        let byId = Dictionary(uniqueKeysWithValues: actions.map { ($0.guid ?? "", $0) })
        XCTAssertEqual(byId[episodes[0].id]?.position, 3)
        XCTAssertEqual(byId[episodes[1].id]?.position, 3)
        XCTAssertLessThan(byId[episodes[2].id]?.position ?? 99, 3)
    }
}
