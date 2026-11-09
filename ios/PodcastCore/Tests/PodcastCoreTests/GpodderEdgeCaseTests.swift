import XCTest
@testable import PodcastCore

/// gpodder subscription edge cases across several sync rounds, driven only through the real
/// PodcastCore pieces (SubscriptionSyncCursor, SubscriptionSyncPlan, FeedDuplicateGrouping).
final class GpodderEdgeCaseTests: XCTestCase {
    // MARK: (1) redirects / update_urls

    func testUpdateUrlsRewriteKeepsOneRemoteKeyAndNoReupload() {
        // Uploaded pre-redirect URL; gpodder.net rewrites it to the new address.
        let keys = SubscriptionSyncCursor.applyingPush([], uploaded: ["http://old.example/feed/"],
            result: PushResult(timestamp: 10, updateUrls: [["http://old.example/feed/", "https://new.example/rss"]]))
        // Rewrite removes `from` before `uploaded` is unioned back in: both keys are known, so
        // a local podcast under either address is not uploaded again.
        XCTAssertTrue(keys.contains(FeedURLEquality.key("https://new.example/rss")))
        let local = [["https://new.example/rss", "http://old.example/feed"]]
        XCTAssertEqual(SubscriptionSyncPlan.urlsToUpload(localPodcasts: local, remoteKeys: keys), [])
        XCTAssertEqual(SubscriptionSyncPlan.urlsToUpload(localPodcasts: [["http://old.example/feed"]], remoteKeys: keys), [])
    }

    func testUpdateUrlsMalformedPairsIgnored() {
        let keys = SubscriptionSyncCursor.applyingPush(["a.example/x"], uploaded: [],
            result: PushResult(timestamp: 1, updateUrls: [["only-one"], [], ["", ""]]))
        XCTAssertEqual(keys, ["a.example/x"])
    }

    func testServerReportsRedirectedUrlForLocalAliasImportsNothing() {
        // Locally stored under the redirect target with the old URL as alias; server lists old URL.
        let local = ["https://new.example/rss", "http://old.example/feed"]
        XCTAssertEqual(SubscriptionSyncPlan.urlsToImport(remote: ["https://OLD.example/feed/"], localFeedURLs: local), [])
        // And the reverse: server already has the new URL, local only knows the old one.
        XCTAssertEqual(SubscriptionSyncPlan.urlsToImport(remote: ["https://new.example/rss"], localFeedURLs: ["http://old.example/feed"]),
                       ["https://new.example/rss"])
    }

    func testParsePushDecodesUpdateUrls() throws {
        let r = try GpodderSubscriptionAPI.parsePush(Data(#"{"timestamp":7,"update_urls":[["feed://a.example/f","http://a.example/f"]]}"#.utf8))
        XCTAssertEqual(r.updateUrls?.first, ["feed://a.example/f", "http://a.example/f"])
        let keys = SubscriptionSyncCursor.applyingPush([], uploaded: ["feed://a.example/f"], result: r)
        XCTAssertEqual(keys, ["a.example/f"]) // same podcast under both spellings
    }

    // MARK: (2) renamed feed / changed feed URL

    func testChangedFeedUrlFoldsIntoOnePodcast() {
        // Old entry + new entry carrying the old URL as alias → one group, loaded https survives.
        let entries: [FeedDuplicateGrouping.Entry] = [
            .init(urls: ["http://old.example/feed"], loaded: true),
            .init(urls: ["https://new.example/rss", "http://old.example/feed/"], loaded: true),
        ]
        let groups = FeedDuplicateGrouping.groups(entries.map(\.urls))
        XCTAssertEqual(groups, [[0, 1]])
        XCTAssertEqual(FeedDuplicateGrouping.survivor(groups[0], entries: entries), 1)
    }

    func testChangedFeedUrlServerRemovesOldWhileAddingNewKeepsSubscription() {
        // Incremental pull: server swapped old for new URL. Local podcast knows both → not unsubscribed.
        let local = [["https://new.example/rss", "http://old.example/feed"]]
        let idx = SubscriptionSyncPlan.podcastsToUnsubscribe(remove: ["http://old.example/feed"],
                                                             add: ["https://new.example/rss"], localPodcasts: local)
        // Bug fixed: was [0] (subscription lost; the add imported nothing because the new URL
        // was already a local alias).
        XCTAssertEqual(idx, [])
        // A podcast that only has the removed URL is still unsubscribed.
        XCTAssertEqual(SubscriptionSyncPlan.podcastsToUnsubscribe(remove: ["http://old.example/feed"],
            add: ["https://new.example/rss"], localPodcasts: [["http://old.example/feed"], local[0]]), [0])
        XCTAssertEqual(SubscriptionSyncPlan.urlsToImport(remote: ["https://new.example/rss"], localFeedURLs: local[0]), [])
    }

    // MARK: (3) re-subscribe after unsubscribe

    func testAddRemoveAddAcrossRoundsLeavesExactlyOneSubscription() {
        let f = "https://pod.example/feed"
        var cursor = SubscriptionSyncCursor()
        // Round 1: full pull with f.
        let p1 = SubscriptionDelta(add: [f], remove: [], timestamp: 100)
        var keys = cursor.applyingPull(p1)
        cursor = .committed(pull: p1, keys: keys, push: nil)
        XCTAssertEqual(cursor, SubscriptionSyncCursor(since: 100, remoteKeys: [FeedURLEquality.key(f)]))
        // Round 2: removed elsewhere → local unsubscribes it.
        let p2 = SubscriptionDelta(add: [], remove: [f + "/"], timestamp: 200)
        XCTAssertEqual(SubscriptionSyncPlan.feedsToUnsubscribe(remove: p2.remove, add: p2.add, localFeedURLs: [f]), [f])
        keys = cursor.applyingPull(p2)
        cursor = .committed(pull: p2, keys: keys, push: nil)
        XCTAssertTrue(cursor.remoteKeys.isEmpty)
        // Round 3: user re-subscribes locally → uploaded once, with server timestamp.
        let p3 = SubscriptionDelta(add: [], remove: [], timestamp: 200)
        keys = cursor.applyingPull(p3)
        let up = SubscriptionSyncPlan.urlsToUpload(localPodcasts: [[f]], remoteKeys: keys)
        XCTAssertEqual(up, [f])
        let push = PushResult(timestamp: 300, updateUrls: nil)
        cursor = .committed(pull: p3, keys: SubscriptionSyncCursor.applyingPush(keys, uploaded: up, result: push), push: push)
        XCTAssertEqual(cursor.since, 300)
        // Round 4: server echoes the add → no re-import, no re-upload (no ghost / duplicate).
        let p4 = SubscriptionDelta(add: [f], remove: [], timestamp: 300)
        keys = cursor.applyingPull(p4)
        XCTAssertEqual(SubscriptionSyncPlan.urlsToImport(remote: p4.add, localFeedURLs: [f]), [])
        XCTAssertEqual(SubscriptionSyncPlan.urlsToUpload(localPodcasts: [[f]], remoteKeys: keys), [])
    }

    func testRemoveAndReAddInSameWindowKeepsSubscription() {
        let f = "http://pod.example/feed"
        XCTAssertEqual(SubscriptionSyncPlan.feedsToUnsubscribe(remove: [f], add: ["https://pod.example/feed/"], localFeedURLs: [f]), [])
        let cursor = SubscriptionSyncCursor(since: 5, remoteKeys: [])
        // applyingPull adds then removes: same-window add+remove ends as removed on the cursor,
        // so the still-subscribed podcast is uploaded again on the next push (self-healing).
        let keys = cursor.applyingPull(SubscriptionDelta(add: [f], remove: [f], timestamp: 6))
        XCTAssertFalse(keys.contains(FeedURLEquality.key(f)))
        XCTAssertEqual(SubscriptionSyncPlan.urlsToUpload(localPodcasts: [[f]], remoteKeys: keys), [f])
    }

    func testFailedRoundRepeatsSameDelta() {
        let cursor = SubscriptionSyncCursor(since: 50, remoteKeys: ["a.example/f"])
        _ = cursor.applyingPull(SubscriptionDelta(add: ["https://b.example/f"], remove: ["a.example/f"], timestamp: 60))
        // Not committed → unchanged; next attempt sends the same since.
        XCTAssertEqual(cursor.since, 50)
        XCTAssertEqual(cursor.remoteKeys, ["a.example/f"])
        XCTAssertEqual(SubscriptionSyncCursor.reset, SubscriptionSyncCursor(since: 0, remoteKeys: []))
    }

    // MARK: (4) repeated import / spelling variants

    func testSameListImportedTwiceAddsNothingSecondTime() {
        let remote = ["https://a.example/feed", "http://A.example/feed/", "feed://a.example//feed",
                      "https://a.example:443/feed", " https://b.example/rss?x=1 ", "https://b.example/rss?x=2"]
        let first = SubscriptionSyncPlan.urlsToImport(remote: remote, localFeedURLs: [])
        XCTAssertEqual(first, ["https://a.example/feed", "https://b.example/rss?x=1", "https://b.example/rss?x=2"])
        XCTAssertEqual(SubscriptionSyncPlan.distinctRemoteCount(remote), 3)
        XCTAssertEqual(SubscriptionSyncPlan.urlsToImport(remote: remote, localFeedURLs: first), [])
        XCTAssertEqual(SubscriptionSyncPlan.urlsToUpload(localPodcasts: first.map { [$0] },
                                                          remoteKeys: FeedURLEquality.keys(remote)), [])
    }

    func testNonHttpRemoteEntriesNeverImported() {
        XCTAssertEqual(SubscriptionSyncPlan.urlsToImport(remote: ["ftp://x.example/f", "", "   "], localFeedURLs: []), [])
    }

    func testDuplicateEntriesAfterDoubleImportFoldToOne() {
        let entries = [["https://a.example/feed"], ["http://a.example/feed/"], ["https://b.example/rss"]]
        XCTAssertEqual(FeedDuplicateGrouping.groups(entries), [[0, 1], [2]])
    }
}
