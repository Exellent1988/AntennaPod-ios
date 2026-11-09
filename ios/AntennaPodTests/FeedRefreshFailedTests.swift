import XCTest
@testable import AntennaPod

/// Android Feed.hasLastUpdateFailed (errorIcon in subscription_grid_item / subscription_list_item).
@MainActor
final class FeedRefreshFailedTests: XCTestCase {
    private func makeFeed() -> PodcastFeed {
        PodcastFeed(
            id: UUID(), title: "f", feedUrl: "https://rf.example/feed", siteLink: nil, imageUrl: nil,
            descriptionText: nil, author: nil, language: nil, fundingUrl: nil, fundingLabel: nil, categories: [],
            isLocked: false, lockedOwner: nil, podcastGuid: nil, episodes: [])
    }

    func testMarkRefreshFailedSetsOnlyThatFeedAndNotLoadError() {
        let store = PodcastStore()
        let saved = store.feeds
        defer { store.feeds = saved }
        let a = makeFeed(), b = makeFeed()
        store.feeds = [a, b]
        store.markRefreshFailed(feedId: a.id, message: "HTTP 500")
        XCTAssertEqual(store.feeds[0].lastRefreshError, "HTTP 500")
        XCTAssertNil(store.feeds[0].loadError, "dedupe/import loadError untouched")
        XCTAssertNil(store.feeds[1].lastRefreshError)
    }

    func testFreshFeedHasNoErrorAndFieldRoundTrips() throws {
        var f = makeFeed()
        XCTAssertNil(f.lastRefreshError, "a successful refresh stores a freshly parsed feed → cleared")
        f.lastRefreshError = "timeout"
        let decoded = try JSONDecoder().decode(PodcastFeed.self, from: JSONEncoder().encode(f))
        XCTAssertEqual(decoded.lastRefreshError, "timeout")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(makeFeed())) as! [String: Any]
        legacy.removeValue(forKey: "lastRefreshError")
        let old = try JSONDecoder().decode(PodcastFeed.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(old.lastRefreshError, "older feeds.json")
    }

    func testAccessibilityLabelMentionsFailure() {
        XCTAssertEqual(SubscriptionRefreshFailedIcon.accessibilityLabel(title: "P", count: 2, failed: false), "P, 2")
        XCTAssertTrue(SubscriptionRefreshFailedIcon.accessibilityLabel(title: "P", count: 0, failed: true).hasPrefix("P, "))
    }
}
