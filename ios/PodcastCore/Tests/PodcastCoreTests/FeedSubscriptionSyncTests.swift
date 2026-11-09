import XCTest
@testable import PodcastCore

final class FeedURLEqualityTests: XCTestCase {
    func testAndroidUrlEqualsVariantsShareOneKey() {
        let variants = [
            "https://Example.COM/Feed/mp3", "http://example.com/feed/mp3", "https://example.com/feed/mp3/",
            "https://example.com//feed//mp3", "  https://example.com/feed/mp3\n", "https://example.com:443/feed/mp3",
            "http://example.com:80/feed/mp3", "feed://example.com/feed/mp3", "itpc://example.com/feed/mp3",
            "pcast://example.com/feed/mp3", "podcast://example.com/feed/mp3", "example.com/feed/mp3",
            "https://example.com/feed/mp3#latest",
        ]
        XCTAssertEqual(Set(variants.map(FeedURLEquality.key)), ["example.com/feed/mp3"])
    }

    func testDifferentPodcastsStayDistinct() {
        XCTAssertNotEqual(FeedURLEquality.key("https://a.example/rss?t=X"), FeedURLEquality.key("https://a.example/rss?t=x"))
        XCTAssertNotEqual(FeedURLEquality.key("https://a.example/rss?id=1"), FeedURLEquality.key("https://a.example/rss?id=2"))
        XCTAssertNotEqual(FeedURLEquality.key("https://a.example:8443/rss"), FeedURLEquality.key("https://a.example/rss"))
        XCTAssertNotEqual(FeedURLEquality.key("https://a.example/rss"), FeedURLEquality.key("https://b.example/rss"))
        XCTAssertNotEqual(FeedURLEquality.key("https://a.example/feed/mp3"), FeedURLEquality.key("https://a.example/feed/m4a"))
        XCTAssertEqual(FeedURLEquality.key(""), "")
        XCTAssertEqual(FeedURLEquality.key("   "), "")
    }

    func testRequestURLKeepsCaseAndQueryButDropsTrailingSlash() {
        XCTAssertEqual(FeedURLEquality.requestURL(" HTTPS://Host.example/Feed/RSS?Token=AbC/ "), "https://Host.example/Feed/RSS?Token=AbC")
        XCTAssertTrue(FeedURLEquality.isHTTP("HTTP://x.example/a"))
        XCTAssertTrue(FeedURLEquality.isHTTP("https://x.example/a"))
        XCTAssertFalse(FeedURLEquality.isHTTP("ftp://x.example/a"))
        XCTAssertFalse(FeedURLEquality.isHTTP("feed://x.example/a"))
        XCTAssertFalse(FeedURLEquality.isHTTP("x.example/a"))
    }
}

final class SubscriptionSyncPlanTests: XCTestCase {
    /// A typical polluted account: the same podcasts under http/https, slash, case and
    /// redirect variants, plus junk. Every podcast is imported exactly once.
    let pollutedServer = [
        "https://feeds.metaebene.me/lnp/mp3",
        "http://feeds.metaebene.me/lnp/mp3/",
        "https://FEEDS.metaebene.me/lnp/mp3",
        "https://logbuch-netzpolitik.de/feed/mp3",        // pre-redirect alias of the line above
        "https://feeds.simplecast.com/54nAGcIl",
        "http://feeds.simplecast.com/54nAGcIl/",
        "https://example.org/a.xml",
        "https://example.org/b.xml",
        "ftp://example.org/c.xml",
        "",
        "   ",
    ]

    func testFreshImportIsCompleteAndDuplicateFree() {
        let todo = SubscriptionSyncPlan.urlsToImport(remote: pollutedServer, localFeedURLs: [])
        // The redirect alias is only known as the same podcast after its first fetch, so on a
        // fresh install it is fetched once; the store then folds it into the target (see
        // FeedDuplicateGroupingTests.testRedirectAliasFoldsIntoTarget).
        XCTAssertEqual(todo, [
            "https://feeds.metaebene.me/lnp/mp3",
            "https://logbuch-netzpolitik.de/feed/mp3",
            "https://feeds.simplecast.com/54nAGcIl",
            "https://example.org/a.xml",
            "https://example.org/b.xml",
        ])
        XCTAssertEqual(Set(todo.map(FeedURLEquality.key)).count, todo.count, "no two imports are the same podcast")
        XCTAssertEqual(SubscriptionSyncPlan.distinctRemoteCount(pollutedServer), 5)
    }

    func testCaseSensitivePathSpellingIsKept() {
        XCTAssertEqual(SubscriptionSyncPlan.urlsToImport(remote: ["https://feeds.simplecast.com/54nAGcIl/"], localFeedURLs: []),
                       ["https://feeds.simplecast.com/54nAGcIl"])
    }

    func testKnownAliasesAreNotImportedAgain() {
        // Local library: LNP stored under its final URL with the pre-redirect URL as alias;
        // The Daily stored as http.
        let local = ["https://feeds.metaebene.me/lnp/mp3", "https://logbuch-netzpolitik.de/feed/mp3",
                     "http://feeds.simplecast.com/54nAGcIl"]
        let todo = SubscriptionSyncPlan.urlsToImport(remote: pollutedServer, localFeedURLs: local)
        XCTAssertEqual(todo, ["https://example.org/a.xml", "https://example.org/b.xml"])
    }

    func testEverythingLocalImportsNothing() {
        let local = ["https://feeds.metaebene.me/lnp/mp3", "https://logbuch-netzpolitik.de/feed/mp3",
                     "https://feeds.simplecast.com/54nAGcIl", "https://example.org/a.xml", "https://example.org/b.xml"]
        XCTAssertEqual(SubscriptionSyncPlan.urlsToImport(remote: pollutedServer, localFeedURLs: local), [])
    }

    func testDifferentQueriesAreDifferentPodcasts() {
        let todo = SubscriptionSyncPlan.urlsToImport(remote: ["https://p.example/rss?id=1", "https://p.example/rss?id=2"],
                                                     localFeedURLs: ["https://p.example/rss?id=1"])
        XCTAssertEqual(todo, ["https://p.example/rss?id=2"])
    }

    // MARK: Push (server-side variant pollution)

    func testPodcastKnownUnderAnyAliasIsNotUploaded() {
        let remote = FeedURLEquality.keys(["http://feeds.metaebene.me/lnp/mp3/", "https://logbuch-netzpolitik.de/feed/mp3"])
        let local: [[String]] = [
            ["https://feeds.metaebene.me/lnp/mp3"],                                      // http variant on server
            ["https://new.example/final.xml", "https://logbuch-netzpolitik.de/feed/mp3"], // alias on server
            ["https://only-local.example/rss"],
        ]
        XCTAssertEqual(SubscriptionSyncPlan.urlsToUpload(localPodcasts: local, remoteKeys: remote),
                       ["https://only-local.example/rss"])
    }

    func testOneUploadPerPodcastAndHttpOnly() {
        let local: [[String]] = [
            ["https://a.example/rss/"], ["http://A.example/rss"],          // stray local twin
            ["https://b.example/final", "https://b-old.example/rss"],
            ["https://b-old.example/rss"],                                  // twin via alias
            ["file:///Users/x/local.xml"], ["ftp://c.example/rss"], [],
        ]
        XCTAssertEqual(SubscriptionSyncPlan.urlsToUpload(localPodcasts: local, remoteKeys: []),
                       ["https://a.example/rss", "https://b.example/final"])
    }

    func testRoundTripImportThenPushUploadsNothing() {
        // After importing the polluted list, the next push must not add any variant back.
        let imported = SubscriptionSyncPlan.urlsToImport(remote: pollutedServer, localFeedURLs: [])
        let up = SubscriptionSyncPlan.urlsToUpload(localPodcasts: imported.map { [$0] },
                                                   remoteKeys: FeedURLEquality.keys(pollutedServer))
        XCTAssertEqual(up, [])
    }

    // MARK: Remote removes

    func testRemoteRemoveMatchesAnyAliasButNotReAdded() {
        let local: [[String]] = [
            ["https://new.example/feed", "https://old.example/podcast.xml"],
            ["https://keep.example/rss"],
            ["https://readd.example/rss"],
        ]
        let idx = SubscriptionSyncPlan.podcastsToUnsubscribe(
            remove: ["http://old.example/podcast.xml/", "https://readd.example/rss"],
            add: ["https://READD.example/rss/"], localPodcasts: local)
        XCTAssertEqual(idx, [0])
        XCTAssertEqual(SubscriptionSyncPlan.feedsToUnsubscribe(remove: ["http://keep.example/rss/"], add: [],
                                                               localFeedURLs: ["https://keep.example/rss", "https://x.example"]),
                       ["https://keep.example/rss"])
    }
}

final class FeedDuplicateGroupingTests: XCTestCase {
    func testVariantsGroupAndDistinctStaySeparate() {
        let g = FeedDuplicateGrouping.groups([
            ["http://a.example/rss"], ["https://b.example/rss"], ["https://A.example/rss/"], ["https://c.example/rss"],
        ])
        XCTAssertEqual(g, [[0, 2], [1], [3]])
    }

    func testRedirectAliasFoldsIntoTarget() {
        // Fresh import fetched the pre-redirect URL: entry 1 recorded its final URL as alias.
        let g = FeedDuplicateGrouping.groups([
            ["https://feeds.metaebene.me/lnp/mp3"],
            ["https://logbuch-netzpolitik.de/feed/mp3", "https://feeds.metaebene.me/lnp/mp3"],
        ])
        XCTAssertEqual(g, [[0, 1]])
    }

    func testTransitiveAliasChainsMerge() {
        // 0~2 via x, 1~2 via y: all three are one podcast even though 0 and 1 share nothing.
        let g = FeedDuplicateGrouping.groups([
            ["https://x.example/rss"], ["https://y.example/rss"], ["https://y.example/rss", "http://x.example/rss"],
        ])
        XCTAssertEqual(g, [[0, 1, 2]])
    }

    func testSurvivorPrefersLoadedHttps() {
        let e: [FeedDuplicateGrouping.Entry] = [
            .init(urls: ["http://a.example/rss"], loaded: true),
            .init(urls: ["https://a.example/rss"], loaded: false),
            .init(urls: ["https://a.example/rss/"], loaded: true),
        ]
        XCTAssertEqual(FeedDuplicateGrouping.survivor([0, 1, 2], entries: e), 2)
        XCTAssertEqual(FeedDuplicateGrouping.survivor([0, 1], entries: e), 0)
        let failed: [FeedDuplicateGrouping.Entry] = [.init(urls: ["http://a"], loaded: false), .init(urls: ["https://a"], loaded: false)]
        XCTAssertEqual(FeedDuplicateGrouping.survivor([0, 1], entries: failed), 0, "all failed: keep first (placeholder)")
    }

    func testNoEntryIsLost() {
        let entries: [[String]] = [["https://a/rss"], ["http://a/rss"], ["https://b/rss"], [], ["https://c/rss", "https://b/rss"]]
        let g = FeedDuplicateGrouping.groups(entries)
        XCTAssertEqual(g.flatMap { $0 }.sorted(), Array(entries.indices), "every entry is in exactly one group")
        XCTAssertEqual(g.count, 3)
    }
}
