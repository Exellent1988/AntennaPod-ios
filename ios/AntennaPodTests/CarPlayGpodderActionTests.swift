import XCTest
@testable import AntennaPod

/// CarPlay Next chapter button → skipToNextChapter; gpodder play-action semantics are covered
/// by GpodderPlayActionTests, this checks the last-chapter skip-episode fallback records them too.
/// Expected values follow Android SynchronizationQueueImpl.enqueueEpisodePlayed.
@MainActor
final class CarPlayGpodderActionTests: PlaybackFixtureTestCase {
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

    func testNextChapterOnLastChapterFallsBackToSkipAndRecordsPosition() async throws {
        settings.smartMarkAsPlayedSeconds = 0
        var ep = episodes[0]
        ep.chapters = [PodcastChapter(title: "One", startTimeSeconds: 0),
                       PodcastChapter(title: "Two", startTimeSeconds: 1)]
        try await playAndWait(ep, past: 1.2)
        XCTAssertTrue(playback.hasChaptersForRemote)
        let at = playback.positionSeconds
        playback.skipToNextChapter()          // on the last chapter → skip episode (Android onNextChapter)
        XCTAssertEqual(playback.currentEpisode?.id, episodes[1].id)
        let a = try XCTUnwrap(action(for: ep))
        XCTAssertTrue(store.playbackState(for: ep.id).isPlayed)
        XCTAssertEqual(Double(a.position ?? -1), at, accuracy: 1.0)
        XCTAssertEqual(a.total, 3)
    }
}
