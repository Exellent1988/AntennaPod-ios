import PodcastCore
import XCTest
@testable import AntennaPod

/// End-to-end gpodder import over the real `GpodderSyncService.subscribeMissing` and
/// `PodcastStore` merge rules, with a fake feed fetch (no network): every server podcast ends up
/// in the library exactly once, failed feeds stay as placeholders, redirect aliases fold.
@MainActor
final class GpodderImportCompletenessTests: XCTestCase {
    private var store: PodcastStore!
    private var saved: [PodcastFeed] = []
    private var savedDeviceId: Any?

    override func setUp() async throws {
        savedDeviceId = UserDefaults.standard.object(forKey: "gpodder.deviceId")
        store = PodcastStore()
        saved = store.feeds
        store.feeds = []
    }

    override func tearDown() async throws {
        store.feeds = saved
        if let savedDeviceId { UserDefaults.standard.set(savedDeviceId, forKey: "gpodder.deviceId") }
        else { UserDefaults.standard.removeObject(forKey: "gpodder.deviceId") }
    }

    private nonisolated static func makeFeed(_ url: String, alternates: [String]? = nil, episodes: [String] = ["e"]) -> PodcastFeed {
        var f = PodcastFeed(
            id: UUID(), title: url, feedUrl: url, siteLink: nil, imageUrl: nil, descriptionText: nil,
            author: nil, language: nil, fundingUrl: nil, fundingLabel: nil, categories: [], isLocked: false,
            lockedOwner: nil, podcastGuid: nil,
            episodes: episodes.map { PodcastEpisode(id: "\(url)#\($0)", title: $0, downloadUrl: "https://e/\($0).mp3",
                                                    mimeType: "audio/mpeg", durationSeconds: 60) })
        f.alternateUrls = alternates
        return f
    }

    /// Fake fetch: `redirects` maps a requested URL to its final URL; `failing` throws.
    /// Stores like `subscribeQuietly` does (match by URL key, keep the stored feedUrl).
    private func fakeSubscribe(redirects: [String: String] = [:], failing: Set<String> = []) -> @Sendable (String) async throws -> Void {
        let store = store!
        return { url in
            if failing.contains(url) { throw URLError(.badServerResponse) }
            try await MainActor.run {
                var incoming = Self.makeFeed(url)
                if let final = redirects[url] { incoming.addAlternateUrl(final) }
                let keys = incoming.urlKeys
                if let i = store.feeds.firstIndex(where: { !$0.urlKeys.isDisjoint(with: keys) }) {
                    for u in incoming.allUrls { store.feeds[i].addAlternateUrl(u) }
                    store.feeds[i].loadError = nil
                } else {
                    store.feeds.append(incoming)
                }
            }
        }
    }

    private let server = [
        "https://feeds.metaebene.me/lnp/mp3",
        "http://feeds.metaebene.me/lnp/mp3/",
        "https://logbuch-netzpolitik.de/feed/mp3",
        "https://feeds.simplecast.com/54nAGcIl",
        "http://FEEDS.simplecast.com/54nAGcIl/",
        "https://broken.example/rss",
        "https://ok.example/a.xml",
        "ftp://ignored.example/rss",
    ]

    func testImportIsCompleteWithPlaceholdersAndNoDuplicates() async {
        let sync = GpodderSyncService()
        let result = await sync.subscribeMissing(
            server, store: store,
            subscribe: fakeSubscribe(redirects: ["https://logbuch-netzpolitik.de/feed/mp3": "https://feeds.metaebene.me/lnp/mp3"],
                                     failing: ["https://broken.example/rss"]))
        store.mergeDuplicateFeeds()
        // Import runs concurrently (importConcurrency): whichever of a redirect pair is stored first keeps
        // its feedUrl, the other becomes an alias. So check groups by urlKeys, never the primary URL.
        XCTAssertEqual(store.feeds.count, 4, "every server podcast exactly once: \(store.feeds.map(\.feedUrl))")
        for key in ["feeds.metaebene.me/lnp/mp3", "logbuch-netzpolitik.de/feed/mp3", "feeds.simplecast.com/54nagcil",
                    "broken.example/rss", "ok.example/a.xml"] {
            XCTAssertEqual(store.feeds.filter { $0.urlKeys.contains(key) }.count, 1, "\(key) in exactly one podcast")
        }
        XCTAssertFalse(store.feeds.contains { $0.urlKeys.contains("ignored.example/rss") }, "non-http URL ignored")
        XCTAssertEqual(result.failures.map(\.url), ["https://broken.example/rss"])
        let broken = store.feeds.first { $0.feedUrl == "https://broken.example/rss" }
        XCTAssertNotNil(broken?.loadError, "failed feed kept as placeholder, not missing")
        let lnp = store.feeds.first { $0.urlKeys.contains("feeds.metaebene.me/lnp/mp3") }
        XCTAssertTrue(lnp?.urlKeys.contains("logbuch-netzpolitik.de/feed/mp3") == true, "redirect source and target fold into one podcast")
    }

    /// Both completion orders of a redirect pair (source first / target first) end as one podcast
    /// that knows both URLs, without the test calling mergeDuplicateFeeds itself.
    func testRedirectPairFoldsInEitherOrder() async {
        for sourceFirst in [true, false] {
            store.feeds = []
            let source = "https://logbuch-netzpolitik.de/feed/mp3", target = "https://feeds.metaebene.me/lnp/mp3"
            let inner = fakeSubscribe(redirects: [source: target])
            let late = sourceFirst ? target : source
            let result = await GpodderSyncService().subscribeMissing([source, target], store: store, subscribe: { url in
                if url == late { try await Task.sleep(nanoseconds: 150_000_000) }
                try await inner(url)
            })
            XCTAssertTrue(result.failures.isEmpty)
            XCTAssertEqual(store.feeds.count, 1, "sourceFirst=\(sourceFirst): \(store.feeds.map(\.allUrls))")
            XCTAssertEqual(store.feeds.first?.urlKeys.isSuperset(of: ["logbuch-netzpolitik.de/feed/mp3", "feeds.metaebene.me/lnp/mp3"]), true)
        }
    }

    func testSecondImportAddsNothing() async {
        let sync = GpodderSyncService()
        let sub = fakeSubscribe(redirects: ["https://logbuch-netzpolitik.de/feed/mp3": "https://feeds.metaebene.me/lnp/mp3"],
                                failing: ["https://broken.example/rss"])
        _ = await sync.subscribeMissing(server, store: store, subscribe: sub)
        store.mergeDuplicateFeeds()
        let count = store.feeds.count
        let again = await sync.subscribeMissing(server, store: store, subscribe: { url in
            XCTFail("re-import fetched \(url)")
        })
        XCTAssertEqual(store.feeds.count, count)
        XCTAssertEqual(again.subscribed, 0)
    }

    func testPushAfterImportUploadsNoVariant() async {
        let sync = GpodderSyncService()
        _ = await sync.subscribeMissing(server, store: store, subscribe: fakeSubscribe(failing: ["https://broken.example/rss"]))
        store.mergeDuplicateFeeds()
        store.feeds.append(Self.makeFeed("https://only-local.example/rss"))
        let up = SubscriptionSyncPlan.urlsToUpload(localPodcasts: store.feeds.map(\.allUrls),
                                                    remoteKeys: FeedURLEquality.keys(server))
        XCTAssertEqual(up, ["https://only-local.example/rss"])
    }

    func testAppWrappersMatchPodcastCore() {
        let urls = ["HTTPS://A.example/X/", "feed://a.example/x", "https://a.example/x?q=1", ""]
        for u in urls {
            XCTAssertEqual(GpodderSyncService.normalizeFeedURL(u), FeedURLEquality.key(u))
            XCTAssertEqual(GpodderSyncService.syncFeedURL(u), FeedURLEquality.requestURL(u))
        }
        XCTAssertEqual(GpodderSyncLogic.urlsToImport(remote: server, localFeedURLs: []),
                       SubscriptionSyncPlan.urlsToImport(remote: server, localFeedURLs: []))
    }
}
