import XCTest
import PodcastCore
@testable import CarPlayLogic

/// Duplicate feed URL spellings and duplicate episode GUIDs at the CarPlay layer.
/// URL equality uses the real PodcastCore `FeedURLEquality.key` (what the app's `FeedURLKey.key` forwards to,
/// Android `UrlChecker.urlEquals`). Merging itself (`FeedLibraryDedupe` / `PodcastStore.mergeDuplicateFeeds`)
/// needs the real PodcastFeed and runs in XCTest (FeedDedupeTests); here CarPlay must list whatever the
/// store holds (unmerged twins during refresh/import), keep per-feed attribution and never trap.
@MainActor
final class CarPlayDuplicateFeedLinuxTests: XCTestCase {
    static let spellings = [
        "http://dup.example.com/feed",     // scheme
        "https://dup.example.com/feed",
        "https://dup.example.com/feed/",   // trailing slash
        "https://DUP.example.com/feed",    // host case
        "https://dup.example.com:443/feed",// explicit default port
        " https://dup.example.com/feed ",  // whitespace
    ]

    func makeStore(guid: String = "same-guid") -> (PodcastStore, [PodcastFeed]) {
        let s = PodcastStore()
        let feeds = Self.spellings.enumerated().map { i, url in
            PodcastFeed(title: "Twin \(i)", feedUrl: url, imageUrl: "https://img.example.com/\(i).png",
                        episodes: [PodcastEpisode(id: guid, title: "Ep (\(i))", pubDateEpochMs: Int64(i)),
                                   PodcastEpisode(id: "own-\(i)", title: "Own \(i)", pubDateEpochMs: 100)])
        }
        s.feeds = feeds
        return (s, feeds)
    }

    func b(_ s: PodcastStore, current: PodcastEpisode? = nil, dl: DownloadService? = nil) -> CarPlayListBuilder {
        CarPlayListBuilder(store: s, downloads: dl, settings: AppSettings(), currentEpisode: current, limit: 100)
    }

    func testEveryURLSpellingTwinIsListedOnceInSubscriptions() {
        let (s, feeds) = makeStore()
        let rows = b(s).subscriptionRows()
        XCTAssertEqual(rows.count, Self.spellings.count)
        XCTAssertEqual(rows.compactMap { r -> UUID? in if case .feed(let id) = r.target { return id }; return nil }.sorted { $0.uuidString < $1.uuidString }, feeds.map(\.id).sorted { $0.uuidString < $1.uuidString })
        XCTAssertEqual(Set(rows.compactMap(\.imageUrl)).count, Self.spellings.count, "Each twin keeps its own artwork")
    }

    func testSameGuidAcrossTwinsKeptPerFeedInEpisodesAndDownloads() {
        let (s, feeds) = makeStore()
        let dl = DownloadService(); dl.downloads = [DownloadedEpisode(id: "same-guid", downloadedAtEpochMs: 1)]
        let builder = b(s, dl: dl)
        let all = builder.allEpisodeInfos()
        XCTAssertEqual(all.count, Self.spellings.count * 2)
        let twins = all.filter { $0.id == "same-guid" }
        XCTAssertEqual(Set(twins.compactMap(\.feedId)), Set(feeds.map(\.id)))
        XCTAssertEqual(Set(twins.map(\.feedTitle)), Set(feeds.map(\.title)))
        XCTAssertEqual(builder.episodeRows(all).count, Self.spellings.count * 2)
        XCTAssertEqual(builder.downloadRows(all).count, Self.spellings.count)
    }

    func testSameGuidWithinOneFeedShownOnceButEverywhereSafe() {
        let s = PodcastStore()
        let f = PodcastFeed(title: "Repeat", feedUrl: "https://r.example.com/feed",
                            episodes: [PodcastEpisode(id: "g", title: "First"), PodcastEpisode(id: "g", title: "Second"),
                                       PodcastEpisode(id: "g", title: "Third")])
        s.feeds = [f]
        s.queue = f.episodes
        let builder = b(s, current: f.episodes[1])
        XCTAssertEqual(builder.allEpisodeInfos().count, 1)
        XCTAssertEqual(builder.feedEpisodeRows(f.id).map(\.title), ["First"])
        XCTAssertEqual(builder.queueSections().last?.1.count, 3, "Queue shows what the store queued")
        XCTAssertEqual(builder.upNextRows().count, 2, "After first matching entry")
        XCTAssertEqual(builder.episodeToPlay(id: "g", feedId: f.id)?.title, "Second", "Loaded copy wins")
        XCTAssertEqual(b(s).episodeToPlay(id: "g", feedId: f.id)?.title, "First")
    }

    func testTapOnEachTwinPlaysThatTwinsCopy() {
        let (s, feeds) = makeStore()
        let builder = b(s)
        for f in feeds {
            let rows = builder.feedEpisodeRows(f.id)
            XCTAssertEqual(rows.count, 2)
            for r in rows { XCTAssertEqual(r.feedId, f.id) }
            let tapped = builder.episodeToPlay(id: "same-guid", feedId: f.id)
            XCTAssertEqual(tapped?.title, f.episodes[0].title)
        }
    }

    func testUpNextKeepsTwinCopiesInQueueOrder() {
        let (s, feeds) = makeStore()
        s.queue = feeds.map { $0.episodes[0] }
        let rows = b(s, current: PodcastEpisode(id: "other", title: "x")).upNextRows()
        XCTAssertEqual(rows.map(\.title), feeds.map { $0.episodes[0].title })
    }

    func testSpellingsAreOneFeedForRealURLEquality() {
        let keys = Set(Self.spellings.map(FeedURLEquality.key))
        XCTAssertEqual(keys.count, 1, "Android urlEquals: scheme, slash, host case, :443, whitespace → same feed: \(keys)")
        XCTAssertNotEqual(FeedURLEquality.key("https://dup.example.com/feed"), FeedURLEquality.key("https://dup.example.com/other"))
    }

    func testAfterStoreMergeCarPlayListsOneFeedWithAllEpisodes() {
        // Survivor shape after mergeDuplicateFeeds: one feed, unique episodes.
        let (s, feeds) = makeStore()
        var survivor = feeds[0]
        var seen = Set<String>()
        survivor.episodes = feeds.flatMap(\.episodes).filter { seen.insert($0.id).inserted }
        s.feeds = [survivor]
        let builder = b(s)
        XCTAssertEqual(builder.subscriptionRows().count, 1)
        XCTAssertEqual(builder.feedEpisodeRows(survivor.id).count, 1 + Self.spellings.count)
        XCTAssertEqual(builder.allEpisodeInfos().filter { $0.id == "same-guid" }.count, 1)
    }
}
