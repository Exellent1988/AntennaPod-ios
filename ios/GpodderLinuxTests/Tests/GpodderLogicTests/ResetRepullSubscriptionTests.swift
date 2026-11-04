import XCTest
import PodcastCore

/// Reset app data → first sync again (since=0), with the real PodcastCore subscription logic.
final class ResetRepullSubscriptionTests: XCTestCase {
    func testFullRepullIsCompleteDeduplicatedAndFoldsAliases() {
        // Server list after earlier rounds: spelling variants and a pre-redirect URL.
        let serverList = ["https://a.example/feed", "http://A.example/feed/", "http://old.example/rss",
                          "https://new.example/rss", "https://c.example/f?id=1", "https://c.example/f?id=2"]
        let cursor = SubscriptionSyncCursor.reset
        let delta = SubscriptionDelta(add: serverList, remove: ["https://gone.example/x"], timestamp: 500)
        let keys = cursor.applyingPull(delta)
        XCTAssertFalse(keys.contains(FeedURLEquality.key("https://gone.example/x")), "since=0 ignores remove")
        // Fresh library: one import per distinct key, nothing lost.
        let imported = SubscriptionSyncPlan.urlsToImport(remote: delta.add, localFeedURLs: [])
        XCTAssertEqual(imported.count, SubscriptionSyncPlan.distinctRemoteCount(serverList))
        XCTAssertEqual(imported.count, 5)
        // Fetch reveals old → new redirect: both entries fold into one podcast.
        var library = imported.map { [$0] }
        library[library.firstIndex(of: ["https://new.example/rss"])!].append("http://old.example/rss")
        let groups = FeedDuplicateGrouping.groups(library)
        XCTAssertEqual(groups.count, 4)
        // Nothing re-uploaded: the server knows every podcast under some URL.
        let survivors = groups.map { g in g.flatMap { library[$0] } }
        XCTAssertEqual(SubscriptionSyncPlan.urlsToUpload(localPodcasts: survivors, remoteKeys: keys), [])
        // A second full pull imports nothing.
        XCTAssertEqual(SubscriptionSyncPlan.urlsToImport(remote: delta.add, localFeedURLs: survivors.flatMap { $0 }), [])
        let committed = SubscriptionSyncCursor.committed(pull: delta, keys: keys, push: nil)
        XCTAssertEqual(committed.since, 500)
    }

    func testUpdateUrlsAfterResetUploadIncludedAndFolded() {
        // Local-only podcast uploaded after reset; gpodder.net rewrites it.
        let keys = SubscriptionSyncCursor.reset.applyingPull(SubscriptionDelta(add: [], remove: [], timestamp: 1))
        let up = SubscriptionSyncPlan.urlsToUpload(localPodcasts: [["http://old.example/rss"]], remoteKeys: keys)
        XCTAssertEqual(up, ["http://old.example/rss"])
        let after = SubscriptionSyncCursor.applyingPush(keys, uploaded: up,
            result: PushResult(timestamp: 2, updateUrls: [["http://old.example/rss", "https://new.example/rss"]]))
        XCTAssertTrue(after.contains(FeedURLEquality.key("https://new.example/rss")))
        // Next pull lists the rewritten URL; local podcast with the old URL as alias imports nothing.
        XCTAssertEqual(SubscriptionSyncPlan.urlsToImport(remote: ["https://new.example/rss"],
                                                        localFeedURLs: ["https://new.example/rss", "http://old.example/rss"]), [])
    }
}
