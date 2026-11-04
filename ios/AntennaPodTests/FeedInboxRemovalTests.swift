import XCTest
@testable import AntennaPod

/// Android nav_feed_context remove_all_inbox_item: one podcast's Inbox episodes leave the Inbox (archive on iOS).
@MainActor
final class FeedInboxRemovalTests: XCTestCase {
    private func feed(_ url: String, episodes: [String]) -> PodcastFeed {
        PodcastFeed(
            id: UUID(), title: url, feedUrl: url, siteLink: nil, imageUrl: nil, descriptionText: nil,
            author: nil, language: nil, fundingUrl: nil, fundingLabel: nil, categories: [], isLocked: false,
            lockedOwner: nil, podcastGuid: nil,
            episodes: episodes.map { PodcastEpisode(id: $0, title: $0, downloadUrl: "https://e/\($0).mp3",
                                                    mimeType: "audio/mpeg", durationSeconds: 60) })
    }

    func testArchivesOnlyThatPodcastsInboxEpisodes() {
        let store = PodcastStore()
        let saved = (store.feeds, store.archivedAtById, store.playbackStates)
        defer { store.feeds = saved.0; store.archivedAtById = saved.1; store.playbackStates = saved.2 }
        let a = feed("https://a.example/feed", episodes: ["ia1", "ia2"])
        let b = feed("https://b.example/feed", episodes: ["ib1"])
        store.feeds = [a, b]
        store.archivedAtById = ["ia2": 42]

        XCTAssertEqual(store.inboxEpisodeIds(inFeed: a.id), ["ia1"])
        store.archiveAllInbox(inFeed: a.id)

        XCTAssertTrue(store.inboxEpisodeIds(inFeed: a.id).isEmpty)
        XCTAssertEqual(store.archivedAtById["ia2"], 42, "existing archive timestamp kept")
        XCTAssertFalse(store.isArchived("ib1"), "other podcasts untouched")
        XCTAssertFalse(store.isPlayed("ia1"), "not marked played")
    }

    func testUnknownFeedIsNoOp() {
        let store = PodcastStore()
        let saved = store.archivedAtById
        defer { store.archivedAtById = saved }
        store.archiveAllInbox(inFeed: UUID())
        XCTAssertEqual(store.archivedAtById, saved)
    }
}
