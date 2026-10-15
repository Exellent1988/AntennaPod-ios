import XCTest
@testable import AntennaPod

/// CarPlayListBuilder duplicate-feed + 100-item cap cases (same as the Linux harness
/// /workspace/carplay-linux-tests, here against the real PodcastStore). Complements CarPlayRobustnessTests.
@MainActor
final class CarPlayListBuilderTests: XCTestCase {
    private var store: PodcastStore!
    private var savedFeeds: [PodcastFeed] = []
    private var savedQueue: [PodcastEpisode] = []
    private var feeds: [PodcastFeed] = []
    private var g1 = "", g2 = ""

    private static func ep(_ id: String, _ title: String, date: Int64?) -> PodcastEpisode {
        var e = CarPlayRobustnessTests.ep(id, title, media: "https://e.example.com/\(id).mp3")
        e.pubDateEpochMs = date
        return e
    }

    override func setUp() async throws {
        store = PodcastStore()
        savedFeeds = store.feeds
        savedQueue = store.queue
        let run = UUID().uuidString.prefix(8)
        g1 = "lb-\(run)-1"; g2 = "lb-\(run)-2"
        feeds = [
            CarPlayRobustnessTests.feed("http://lb-\(run).example.com/feed", title: "LB http",
                                        episodes: [Self.ep(g1, "One (http)", date: 3), Self.ep(g2, "Two (http)", date: 2)]),
            CarPlayRobustnessTests.feed("https://lb-\(run).example.com/feed", title: "LB https",
                                        episodes: [Self.ep(g1, "One (https)", date: 3)]),
            CarPlayRobustnessTests.feed("https://lb-\(run).example.com/feed/", title: "LB slash",
                                        episodes: [Self.ep(g2, "Two (slash)", date: 2)]),
        ]
        store.feeds = savedFeeds + feeds
        store.queue = [feeds[0].episodes[0], feeds[1].episodes[0], feeds[2].episodes[0]]
    }

    override func tearDown() async throws {
        store.feeds = savedFeeds
        store.queue = savedQueue
    }

    private func builder(current: PodcastEpisode? = nil, limit: Int = 500) -> CarPlayListBuilder {
        CarPlayListBuilder(store: store, downloads: nil, settings: nil, currentEpisode: current, limit: limit)
    }

    private func ours(_ infos: [CarPlayEpisodeInfo]) -> [CarPlayEpisodeInfo] {
        infos.filter { i in feeds.contains { $0.id == i.feedId } }
    }

    func testEpisodesTabTwinsKeepOwnFeedTitleAndArtwork() {
        let twins = ours(builder().allEpisodeInfos()).filter { $0.id == g1 }
        XCTAssertEqual(Set(twins.compactMap(\.feedId)), [feeds[0].id, feeds[1].id])
        XCTAssertEqual(Set(twins.map(\.feedTitle)), ["LB http", "LB https"])
        XCTAssertEqual(Set(twins.compactMap(\.artwork)),
                       ["https://img.example.com/LB http.png", "https://img.example.com/LB https.png"])
    }

    func testDownloadedTwinsBothListed() {
        let dl = ours(builder().allEpisodeInfos()).map { var i = $0; i.isDownloaded = i.id == g1; i.downloadedAtEpochMs = 1; return i }
        let rows = CarPlayParity.downloads(dl, sort: .newestFirst, limit: 100)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(Set(rows.compactMap(\.feedId)), [feeds[0].id, feeds[1].id])
    }

    func testEveryEpisodeRowTapPlaysItsOwnCopy() {
        let b = builder()
        let rows = b.episodeRows(ours(b.allEpisodeInfos()))
        XCTAssertEqual(rows.count, 4)
        for row in rows {
            guard case .episode(let id) = row.target else { return XCTFail("episode row") }
            XCTAssertEqual(b.episodeToPlay(id: id, feedId: row.feedId)?.title, row.title)
        }
    }

    func testLoadedEpisodeWinsOverRowFeed() {
        let cur = feeds[1].episodes[0]
        XCTAssertEqual(builder(current: cur).episodeToPlay(id: g1, feedId: feeds[0].id)?.title, "One (https)")
    }

    func testListsCapAtAndroidAutoLimit() {
        let run = UUID().uuidString.prefix(8)
        let many = (0..<150).map { Self.ep("cap-\(run)-\($0)", "Ep \($0)", date: Int64($0)) }
        let big = CarPlayRobustnessTests.feed("https://cap-\(run).example.com/feed", title: "Cap", episodes: many)
        store.feeds = savedFeeds + feeds + [big]
        store.queue = many
        XCTAssertEqual(CarPlayParity.itemLimit(templateMax: 0), 100)
        XCTAssertEqual(CarPlayParity.itemLimit(templateMax: 500), 100)
        XCTAssertEqual(CarPlayParity.itemLimit(templateMax: 12), 12)
        let b = builder(current: many[10], limit: 100)
        XCTAssertEqual(b.feedEpisodeRows(big.id).count, 100)
        XCTAssertEqual(b.feedEpisodeRows(big.id).first?.title, "Ep 149")
        XCTAssertEqual(b.episodeRows(b.allEpisodeInfos()).count, 100)
        XCTAssertEqual(b.queueSections().last?.1.count, 100)
        XCTAssertEqual(b.upNextRows().count, 100)
        XCTAssertEqual(b.upNextRows().first?.title, "Ep 11")
        XCTAssertLessThanOrEqual(b.subscriptionRows().count, 100)
        let dl = b.allEpisodeInfos().map { var i = $0; i.isDownloaded = true; return i }
        XCTAssertEqual(CarPlayParity.downloads(dl, sort: .newestFirst, limit: 100).count, 100)
    }
}
