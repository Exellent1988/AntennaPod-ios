import XCTest
@testable import CarPlayLogic

/// Linux run of the real CarPlayListBuilder/CarPlayParity/CarPlayBrowseModel against stubbed stores.
/// Mirrors ios/AntennaPodTests/CarPlayListBuilderTests.swift (+ CarPlayRobustnessTests cases).
@MainActor
final class CarPlayListBuilderLinuxTests: XCTestCase {
    var store: PodcastStore!
    var downloads: DownloadService!
    var settings: AppSettings!
    var feeds: [PodcastFeed] = []

    static func ep(_ id: String, _ title: String, date: Int64? = nil) -> PodcastEpisode {
        PodcastEpisode(id: id, title: title, pubDateEpochMs: date)
    }

    override func setUp() async throws {
        store = PodcastStore(); downloads = DownloadService(); settings = AppSettings()
        feeds = [
            PodcastFeed(title: "Twin http", feedUrl: "http://dup.example.com/feed", imageUrl: "https://img.example.com/http.png",
                        episodes: [Self.ep("g1", "One (http)", date: 3), Self.ep("g2", "Two (http)", date: 2)]),
            PodcastFeed(title: "Twin https", feedUrl: "https://dup.example.com/feed", imageUrl: "https://img.example.com/https.png",
                        episodes: [Self.ep("g1", "One (https)", date: 3), Self.ep("g1", "One (https, repeated)", date: 3)]),
            PodcastFeed(title: "Twin slash", feedUrl: "https://dup.example.com/feed/", imageUrl: "https://img.example.com/slash.png",
                        episodes: [Self.ep("g2", "Two (slash)", date: 2)]),
            PodcastFeed(title: "Parse failed", feedUrl: "https://broken.example.com/feed", episodes: []),
        ]
        store.feeds = feeds
        store.queue = [feeds[0].episodes[0], feeds[1].episodes[0], feeds[2].episodes[0], feeds[0].episodes[1]]
    }

    func builder(current: PodcastEpisode? = nil, limit: Int = 100, dl: Bool = false) -> CarPlayListBuilder {
        CarPlayListBuilder(store: store, downloads: dl ? downloads : nil, settings: settings, currentEpisode: current, limit: limit)
    }

    // MARK: Episodes / Downloads: twins not dropped

    func testEpisodesTabKeepsTwinsAcrossFeedsWithOwnAttribution() {
        let b = builder()
        let all = b.allEpisodeInfos()
        XCTAssertEqual(all.count, 4, "http×2 + https×1 (in-feed repeat once) + slash×1")
        let g1 = all.filter { $0.id == "g1" }
        XCTAssertEqual(Set(g1.compactMap(\.feedId)), [feeds[0].id, feeds[1].id])
        XCTAssertEqual(Set(g1.map(\.feedTitle)), ["Twin http", "Twin https"])
        XCTAssertEqual(Set(g1.compactMap(\.artwork)), ["https://img.example.com/http.png", "https://img.example.com/https.png"])
        let rows = b.episodeRows(all)
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(Set(rows.compactMap(\.feedId)).count, 3)
    }

    func testDownloadsTabKeepsDownloadedTwins() {
        downloads.downloads = [DownloadedEpisode(id: "g1", downloadedAtEpochMs: 10, byteSize: 5)]
        let b = builder(dl: true)
        let rows = b.downloadRows(b.allEpisodeInfos())
        XCTAssertEqual(rows.count, 2, "Both feeds' copies of a downloaded GUID listed")
        XCTAssertEqual(Set(rows.compactMap(\.feedId)), [feeds[0].id, feeds[1].id])
        let nb = builder(dl: false)
        XCTAssertTrue(nb.downloadRows(nb.allEpisodeInfos()).isEmpty, "No DownloadService: empty, no crash")
    }

    // MARK: Feed episode list

    func testFeedEpisodeListUsesOwnFeedTitleAndArtwork() {
        store.settingsByFeed[feeds[1].id] = FeedSettings(customTitle: "My HTTPS")
        let b = builder()
        let https = b.feedEpisodeRows(feeds[1].id)
        XCTAssertEqual(https.count, 1, "Same GUID repeated inside one feed shown once")
        XCTAssertEqual(https[0].title, "One (https)")
        XCTAssertEqual(https[0].feedId, feeds[1].id)
        XCTAssertEqual(https[0].imageUrl, "https://img.example.com/https.png")
        XCTAssertFalse(https[0].detail?.contains("Twin") ?? false, "Feed list hides feed title")
        let info = b.info(feeds[1].episodes[0], feed: feeds[1])
        XCTAssertEqual(info.feedTitle, "My HTTPS", "displayTitle (custom) of this feed, not the twin")
        XCTAssertEqual(b.feedEpisodeRows(feeds[0].id).map(\.title), ["One (http)", "Two (http)"])
        XCTAssertTrue(b.feedEpisodeRows(feeds[3].id).isEmpty)
        XCTAssertTrue(b.feedEpisodeRows(UUID()).isEmpty)
    }

    func testEpisodeArtworkWinsOverFeedArtwork() {
        var e = Self.ep("art", "Art"); e.imageUrl = "https://img.example.com/item.png"
        XCTAssertEqual(builder().info(e, feed: feeds[0]).artwork, "https://img.example.com/item.png")
        XCTAssertEqual(builder().info(Self.ep("x", "x"), feed: nil).artwork, nil)
    }

    // MARK: Subscriptions

    func testSubscriptionsListEveryTwinAndFailedFeedOnce() {
        let ids = builder().subscriptionRows().compactMap { r -> UUID? in if case .feed(let id) = r.target { return id } else { return nil } }
        XCTAssertEqual(Set(ids), Set(feeds.map(\.id)))
        XCTAssertEqual(ids.count, feeds.count)
    }

    // MARK: Queue / Up Next

    func testQueueSectionsAndUpNextDoNotCollapseDuplicates() {
        let b = builder(current: feeds[1].episodes[0])
        let s = b.queueSections()
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s[0].0, "Currently playing")
        XCTAssertEqual(s[1].0, "Queue")
        XCTAssertEqual(s[1].1.count, 4)
        XCTAssertEqual(b.upNextRows().map(\.title), ["One (https)", "Two (slash)", "Two (http)"])
        XCTAssertEqual(builder(current: Self.ep("nq", "x")).upNextRows().count, 4, "Current not queued: whole queue")
        XCTAssertNil(builder().queueSections()[0].0, "No current: single untitled section")
        store.queue = []
        XCTAssertTrue(b.upNextRows().isEmpty)
    }

    // MARK: Tap → episode

    func testTapPlaysRowsOwnFeedCopy() {
        let b = builder()
        XCTAssertEqual(b.episodeToPlay(id: "g1", feedId: feeds[1].id)?.title, "One (https)")
        XCTAssertEqual(b.episodeToPlay(id: "g1", feedId: feeds[0].id)?.title, "One (http)")
        XCTAssertEqual(b.episodeToPlay(id: "g2", feedId: feeds[2].id)?.title, "Two (slash)")
        XCTAssertEqual(b.episodeToPlay(id: "g1", feedId: nil)?.title, "One (http)", "No feed: queue first")
        XCTAssertNil(b.episodeToPlay(id: "missing", feedId: feeds[3].id))
        let cur = feeds[1].episodes[0]
        XCTAssertEqual(builder(current: cur).episodeToPlay(id: "g1", feedId: feeds[0].id)?.title, "One (https)",
                       "Loaded episode wins")
    }

    func testTapRowFeedIdRoundTrips() {
        let b = builder()
        for row in b.episodeRows(b.allEpisodeInfos()) {
            guard case .episode(let id) = row.target else { return XCTFail() }
            let ep = b.episodeToPlay(id: id, feedId: row.feedId)
            XCTAssertEqual(ep?.title, row.title, "Row \(row.title) plays its own copy")
        }
    }

    // MARK: 100-item caps

    func testAllListsCapAt100() {
        let many = (0..<150).map { Self.ep("m\($0)", "Ep \($0)", date: Int64($0)) }
        let big = PodcastFeed(title: "Big", feedUrl: "https://big.example.com", episodes: many)
        let lots = (0..<150).map { PodcastFeed(title: "F\($0)", feedUrl: "https://f\($0).example.com", episodes: []) }
        store.feeds = [big] + lots
        store.queue = many
        downloads.downloads = many.map { DownloadedEpisode(id: $0.id, downloadedAtEpochMs: 1) }
        XCTAssertEqual(CarPlayParity.itemLimit(templateMax: 0), 100)
        XCTAssertEqual(CarPlayParity.itemLimit(templateMax: 500), 100)
        XCTAssertEqual(CarPlayParity.itemLimit(templateMax: 12), 12)
        let b = builder(current: many[10], limit: CarPlayParity.itemLimit(templateMax: 0), dl: true)
        let all = b.allEpisodeInfos()
        XCTAssertEqual(all.count, 150)
        XCTAssertEqual(b.episodeRows(all).count, 100)
        XCTAssertEqual(b.episodeRows(all).first?.title, "Ep 149", "Newest first, cap keeps newest")
        XCTAssertEqual(b.downloadRows(all).count, 100)
        XCTAssertEqual(b.feedEpisodeRows(big.id).count, 100)
        XCTAssertEqual(b.subscriptionRows().count, 100)
        XCTAssertEqual(b.queueSections().last?.1.count, 100)
        XCTAssertEqual(b.upNextRows().count, 100)
        XCTAssertEqual(b.upNextRows().first?.title, "Ep 11")
        XCTAssertEqual(builder(limit: 12).episodeRows(all).count, 12)
    }

    func testListSnapshotIgnoresPlayingIdNotInList() {
        let rows = builder().episodeRows(builder().allEpisodeInfos())
        XCTAssertEqual(CarPlayListSnapshot(rows: rows, playingEpisodeId: "zzz"), CarPlayListSnapshot(rows: rows, playingEpisodeId: nil))
        XCTAssertNotEqual(CarPlayListSnapshot(rows: rows, playingEpisodeId: "g1"), CarPlayListSnapshot(rows: rows, playingEpisodeId: nil))
    }
}
