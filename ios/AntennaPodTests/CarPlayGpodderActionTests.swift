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

    /// Fixture episodes in a subscribed http feed + private outbox, so `recordGpodderPlayAction` queues.
    private func attachOutbox(_ eps: [PodcastEpisode]) -> GpodderActionQueue {
        let queue = GpodderActionQueue(fileURL: fixtureDir.appendingPathComponent("gpodder-queue.json"))
        store.gpodderActionQueue = queue
        store.isGpodderActionRecordingEnabled = { true }
        let savedFeeds = store.feeds
        store.feeds.append(PodcastFeed(
            id: UUID(), title: "CP feed", feedUrl: "https://example.com/cp-\(UUID().uuidString).xml", siteLink: nil,
            imageUrl: nil, descriptionText: "", author: nil, language: nil, fundingUrl: nil, fundingLabel: nil,
            categories: [], isLocked: false, lockedOwner: nil, podcastGuid: nil,
            episodes: eps.map { var e = $0; e.downloadUrl = "https://example.com/\(e.id).mp3"; return e }))
        addTeardownBlock { @MainActor in self.store.feeds = savedFeeds }
        return queue
    }

    private func chapteredFirstEpisode() -> PodcastEpisode {
        var ep = episodes[0]
        ep.chapters = [PodcastChapter(title: "One", startTimeSeconds: 0),
                       PodcastChapter(title: "Two", startTimeSeconds: 1)]
        return ep
    }

    /// Default Keep skipped episodes (on): Next chapter on the last chapter → kept skip. Episode stays
    /// unplayed in the queue with its position; gpodder gets the real position, not total.
    func testNextChapterOnLastChapterKeptSkipUploadsRealPosition() async throws {
        settings.keepSkippedEpisodes = true
        settings.smartMarkAsPlayedSeconds = 0
        let ep = chapteredFirstEpisode()
        let outbox = attachOutbox(episodes)
        try await playAndWait(ep, past: 1.2)
        XCTAssertTrue(playback.hasChaptersForRemote)
        let at = playback.positionSeconds
        playback.skipToNextChapter()
        XCTAssertEqual(playback.currentEpisode?.id, episodes[1].id, "Still advances")
        let state = store.playbackState(for: ep.id)
        XCTAssertFalse(state.isPlayed)
        XCTAssertEqual(state.positionSeconds, at, accuracy: 0.6, "Position kept for resume")
        XCTAssertTrue(store.queue.contains { $0.id == ep.id }, "Stays in the queue")
        let a = try XCTUnwrap(action(for: ep))
        XCTAssertEqual(Double(a.position ?? -1), at, accuracy: 1.0)
        XCTAssertLessThan(a.position ?? 3, 3)
        let queued = try XCTUnwrap(outbox.snapshot.last { $0.guid == ep.id }, "Persistent outbox entry")
        XCTAssertEqual(Double(queued.position ?? -1), at, accuracy: 1.0)
        XCTAssertLessThan(queued.position ?? 3, 3, "Kept skip: real position, not total")
        XCTAssertEqual(queued.total, 3)
    }

    /// Keep off: the fallback marks played and leaves the queue, still with the real position (Android).
    func testNextChapterOnLastChapterWithKeepOffMarksPlayedAndUploadsRealPosition() async throws {
        settings.keepSkippedEpisodes = false
        settings.smartMarkAsPlayedSeconds = 0
        let ep = chapteredFirstEpisode()
        let outbox = attachOutbox(episodes)
        try await playAndWait(ep, past: 1.2)
        let at = playback.positionSeconds
        playback.skipToNextChapter()
        XCTAssertEqual(playback.currentEpisode?.id, episodes[1].id)
        XCTAssertTrue(store.playbackState(for: ep.id).isPlayed)
        XCTAssertFalse(store.queue.contains { $0.id == ep.id })
        let queued = try XCTUnwrap(outbox.snapshot.last { $0.guid == ep.id })
        XCTAssertEqual(Double(queued.position ?? -1), at, accuracy: 1.0)
        XCTAssertLessThan(queued.position ?? 3, 3)
    }
}
