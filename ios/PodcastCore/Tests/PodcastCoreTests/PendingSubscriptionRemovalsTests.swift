import XCTest
@testable import PodcastCore

/// Android SynchronizationQueue removed-feeds parity: local unsubscribes queued until the
/// server confirmed them; matching by FeedURLEquality over all of a podcast's URLs.
final class PendingSubscriptionRemovalsTests: XCTestCase {
    let pod = ["https://new.example/rss", "http://old.example/feed"]

    func testRecordDedupesByAnyAliasAndCancelOnResubscribe() {
        var p = PendingSubscriptionRemovals()
        p.record(pod)
        p.record(["http://NEW.example/rss/"])
        XCTAssertEqual(p.entries.count, 1)
        XCTAssertEqual(p.entries[0].count, 3, "spelling kept for the remove")
        XCTAssertTrue(p.contains("https://old.example/feed/"))
        p.cancel(["http://old.example/feed"]) // re-subscribed under the alias
        XCTAssertTrue(p.isEmpty)
    }

    func testPullAddsOfPendingRemovesAreIgnored() {
        var p = PendingSubscriptionRemovals(); p.record(pod)
        XCTAssertEqual(p.filteringPull(["http://old.example/feed/", "https://b.example/f"]), ["https://b.example/f"])
    }

    func testAbsorbingPullKeepsServerSpellingForTheRemove() {
        var p = PendingSubscriptionRemovals(); p.record(["https://a.example/f"])
        XCTAssertEqual(p.absorbingPull(["http://a.example/f/", "https://b.example/f"]), ["https://b.example/f"])
        XCTAssertEqual(p.entries, [["https://a.example/f", "http://a.example/f/"]])
        XCTAssertEqual(p.urlsToRemove(remoteKeys: [FeedURLEquality.key("https://a.example/f")]),
                       ["https://a.example/f", "http://a.example/f/"])
    }

    func testUploadSendsServerKnownAddressesElseFeedURL() {
        var p = PendingSubscriptionRemovals(); p.record(pod); p.record(["https://c.example/f/"])
        let remote: Set<String> = [FeedURLEquality.key("http://old.example/feed")]
        XCTAssertEqual(p.urlsToRemove(remoteKeys: remote), ["http://old.example/feed", "https://c.example/f/"])
    }

    func testConfirmDropsOnlyUploadedEntriesAndRemoteKeysForget() {
        var p = PendingSubscriptionRemovals(); p.record(pod)
        let sent = p
        p.record(["https://later.example/f"]) // unsubscribed during the upload
        p.confirm(sent)
        XCTAssertEqual(p.entries, [["https://later.example/f"]])
        let keys = sent.forgetting(FeedURLEquality.keys(pod + ["https://x.example/y"]))
        XCTAssertEqual(keys, [FeedURLEquality.key("https://x.example/y")])
    }

    func testCodableRoundTrip() throws {
        var p = PendingSubscriptionRemovals(); p.record(pod)
        let back = try JSONDecoder().decode(PendingSubscriptionRemovals.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back, p)
    }

    func testEmptyAndNonHttpIgnored() {
        var p = PendingSubscriptionRemovals(); p.record([]); p.record(["", "  "])
        XCTAssertTrue(p.isEmpty)
    }
}
