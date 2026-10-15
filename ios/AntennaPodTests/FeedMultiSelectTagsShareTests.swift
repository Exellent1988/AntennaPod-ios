import XCTest
@testable import AntennaPod

/// Android TagSettingsDialog common tags (TagSettingsDialog.java:57-62) and FeedMenuHandler share_feed
/// visibility (single non-local podcast, FeedMenuHandler.java:40).
@MainActor
final class FeedMultiSelectTagsShareTests: XCTestCase {
    private func feed(_ url: String) -> PodcastFeed {
        PodcastFeed(
            id: UUID(), title: url, feedUrl: url, siteLink: nil, imageUrl: nil, descriptionText: nil,
            author: nil, language: nil, fundingUrl: nil, fundingLabel: nil, categories: [], isLocked: false,
            lockedOwner: nil, podcastGuid: nil, episodes: [])
    }

    func testCommonTagsAreTheIntersectionIgnoringCase() {
        XCTAssertEqual(FeedTagsSheet.commonTags([["News", "Tech"], ["tech", "Daily"], ["TECH", "News"]]), ["Tech"])
    }

    func testCommonTagsOfOnePodcastAreItsTags() {
        XCTAssertEqual(FeedTagsSheet.commonTags([["B", "A"]]), ["A", "B"])
        XCTAssertEqual(FeedTagsSheet.commonTags([]), [])
    }

    func testAddingAndRemovingACommonTagTouchesEverySelectedPodcastOnly() {
        let store = PodcastStore()
        let saved = store.tagsByFeedId
        defer { store.tagsByFeedId = saved }
        let a = UUID(), b = UUID()
        store.tagsByFeedId = [a: ["Tech", "Only A"], b: ["Tech"]]
        // What the sheet does for a common tag (untick) and a new tag (add), for [a, b].
        [a, b].forEach { store.removeTag("Tech", from: $0) }
        [a, b].forEach { store.addTag("Daily", to: $0) }
        XCTAssertEqual(store.tags(for: a), ["Daily", "Only A"])
        XCTAssertEqual(store.tags(for: b), ["Daily"])
    }

    func testShareOnlyForHttpFeeds() {
        XCTAssertNotNil(FeedMultiSelectModifier.shareableFeedURL(feed("https://example.com/feed")))
        XCTAssertNil(FeedMultiSelectModifier.shareableFeedURL(feed("antennapod_local:folder")))
    }
}
