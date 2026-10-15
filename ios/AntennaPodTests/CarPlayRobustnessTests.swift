import XCTest
@testable import AntennaPod

/// Beta crash context: duplicate feed URLs / episode GUIDs. CarPlay lists must build without trapping,
/// list every subscribed feed (no dedupe in CarPlay) and keep per-feed attribution.
@MainActor
final class CarPlayRobustnessTests: XCTestCase {
    private var store: PodcastStore!
    private var savedFeeds: [PodcastFeed] = []
    private var savedQueue: [PodcastEpisode] = []
    private var feeds: [PodcastFeed] = []

    static func feed(_ url: String, title: String, episodes: [PodcastEpisode]) -> PodcastFeed {
        PodcastFeed(id: UUID(), title: title, feedUrl: url, siteLink: nil, imageUrl: "https://img.example.com/\(title).png",
                    descriptionText: "", author: "Author", language: nil, fundingUrl: nil, fundingLabel: nil,
                    categories: [], isLocked: false, lockedOwner: nil, podcastGuid: nil, episodes: episodes)
    }

    static func ep(_ guid: String, _ title: String, media: String) -> PodcastEpisode {
        PodcastEpisode(id: guid, title: title, downloadUrl: media, mimeType: "audio/mpeg", durationSeconds: 600)
    }

    override func setUp() async throws {
        store = PodcastStore()
        savedFeeds = store.feeds
        savedQueue = store.queue
        let run = UUID().uuidString.prefix(8)
        let g1 = "dup-\(run)-1", g2 = "dup-\(run)-2"
        feeds = [
            Self.feed("http://dup-\(run).example.com/feed", title: "Twin http",
                      episodes: [Self.ep(g1, "One (http)", media: "http://dup.example.com/1.mp3"),
                                 Self.ep(g2, "Two (http)", media: "http://dup.example.com/2.mp3")]),
            Self.feed("https://dup-\(run).example.com/feed", title: "Twin https",
                      episodes: [Self.ep(g1, "One (https)", media: "https://dup.example.com/1.mp3"),
                                 Self.ep(g1, "One (https, repeated)", media: "https://dup.example.com/1.mp3")]),
            Self.feed("https://dup-\(run).example.com/feed/", title: "Twin slash",
                      episodes: [Self.ep(g2, "Two (slash)", media: "https://dup.example.com/2.mp3")]),
            Self.feed("https://broken-\(run).example.com/feed", title: "Parse failed", episodes: []),
        ]
        store.feeds = savedFeeds + feeds
        store.queue = [feeds[0].episodes[0], feeds[1].episodes[0], feeds[2].episodes[0], feeds[0].episodes[1]]
    }

    override func tearDown() async throws {
        store.feeds = savedFeeds
        store.queue = savedQueue
    }

    private func builder(current: PodcastEpisode? = nil) -> CarPlayListBuilder {
        CarPlayListBuilder(store: store, downloads: nil, settings: nil, currentEpisode: current, limit: 500)
    }

    func testSubscriptionsKeepEveryTwinAndTheFailedFeed() {
        let rows = builder().subscriptionRows()
        let ids = rows.compactMap { r -> UUID? in if case .feed(let id) = r.target { return id } else { return nil } }
        for f in feeds { XCTAssertTrue(ids.contains(f.id), "\(f.title) listed") }
        XCTAssertEqual(Set(ids).count, ids.count, "No feed listed twice")
    }

    func testPerFeedListsUseTheirOwnFeedAndSurviveDuplicates() {
        let b = builder()
        XCTAssertEqual(b.feedEpisodeRows(feeds[0].id).map(\.title).sorted(), ["One (http)", "Two (http)"])
        let https = b.feedEpisodeRows(feeds[1].id)
        XCTAssertEqual(https.count, 1, "Same GUID repeated inside one feed shown once")
        XCTAssertEqual(https.first?.feedId, feeds[1].id)
        XCTAssertEqual(https.first?.imageUrl, "https://img.example.com/Twin https.png", "Own feed artwork, not the twin's")
        XCTAssertEqual(b.feedEpisodeRows(feeds[2].id).map(\.title), ["Two (slash)"])
        XCTAssertTrue(b.feedEpisodeRows(feeds[3].id).isEmpty, "Failed parse: empty list, no crash")
        XCTAssertTrue(b.feedEpisodeRows(UUID()).isEmpty, "Unknown feed id")
    }

    func testEpisodesAndDownloadsBuildWithDuplicateGuidsAcrossFeeds() {
        let b = builder()
        let all = b.allEpisodeInfos().filter { info in feeds.contains { $0.id == info.feedId } }
        XCTAssertEqual(all.count, 4, "http×2 + https×1 + slash×1: twins across feeds both kept")
        let rows = b.episodeRows(b.allEpisodeInfos())
        XCTAssertTrue(rows.contains { $0.title == "One (http)" })
        XCTAssertTrue(rows.contains { $0.title == "One (https)" })
        XCTAssertTrue(b.downloadRows(b.allEpisodeInfos()).isEmpty, "No DownloadService: empty, no crash")
        var dl = all.map { var i = $0; i.isDownloaded = true; i.downloadedAtEpochMs = 1; return i }
        dl += dl
        XCTAssertEqual(CarPlayParity.downloads(dl, sort: .newestFirst, limit: 500).count, dl.count)
    }

    func testQueueAndUpNextWithDuplicateIds() {
        let current = feeds[1].episodes[0]   // GUID shared with the first queue item
        let b = builder(current: current)
        let sections = b.queueSections()
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].1.count, 1, "Currently playing")
        XCTAssertEqual(sections[1].1.count, 4, "Queue rows incl. duplicate GUIDs")
        let upNext = b.upNextRows()
        XCTAssertEqual(upNext.count, 3, "After the first matching queue entry")
        XCTAssertEqual(upNext.map(\.title), ["One (https)", "Two (slash)", "Two (http)"], "Each entry keeps its own episode")
        XCTAssertTrue(builder(current: Self.ep("not-queued", "x", media: "https://e/x.mp3")).upNextRows().count == 4)
        store.queue = []
        XCTAssertTrue(b.upNextRows().isEmpty)
        XCTAssertEqual(b.queueSections().last?.1.count, 0)
    }

    func testTapPlaysTheRowsOwnFeedCopy() {
        let b = builder()
        let guid = feeds[0].episodes[0].id
        XCTAssertEqual(b.episodeToPlay(id: guid, feedId: feeds[1].id)?.title, "One (https)")
        XCTAssertEqual(b.episodeToPlay(id: guid, feedId: feeds[0].id)?.title, "One (http)")
        XCTAssertNotNil(b.episodeToPlay(id: guid, feedId: nil))
        XCTAssertNil(b.episodeToPlay(id: "missing", feedId: feeds[3].id))
    }
}
