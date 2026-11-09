import XCTest
@testable import AntennaPod

/// Android feeditem_options remove_inbox_item (FeedItemMenuHandler canRemoveFromInbox = item.isNew()).
@MainActor
final class EpisodeRemoveFromInboxTests: XCTestCase {
    func testRemoveFromInboxArchivesOnlyThatEpisode() {
        let store = PodcastStore()
        let saved = (store.feeds, store.archivedAtById, store.playbackStates)
        defer { store.feeds = saved.0; store.archivedAtById = saved.1; store.playbackStates = saved.2 }
        let feed = PodcastFeed(
            id: UUID(), title: "f", feedUrl: "https://rfi.example/feed", siteLink: nil, imageUrl: nil,
            descriptionText: nil, author: nil, language: nil, fundingUrl: nil, fundingLabel: nil, categories: [],
            isLocked: false, lockedOwner: nil, podcastGuid: nil,
            episodes: ["rfi1", "rfi2"].map { PodcastEpisode(id: $0, title: $0, downloadUrl: "https://e/\($0).mp3",
                                                            mimeType: "audio/mpeg", durationSeconds: 60) })
        store.feeds = [feed]
        store.archivedAtById = [:]
        XCTAssertTrue(store.isInInbox("rfi1"))

        store.removeFromInbox("rfi1")

        XCTAssertFalse(store.isInInbox("rfi1"))
        XCTAssertTrue(store.isArchived("rfi1"))
        XCTAssertFalse(store.isPlayed("rfi1"), "played state unchanged")
        XCTAssertTrue(store.isInInbox("rfi2"))
        XCTAssertFalse(store.isInInbox("not-subscribed"))
    }
}
