import XCTest
@testable import AntennaPod

final class CarPlayParityTests: XCTestCase {
    private func ep(_ id: String, title: String? = nil, date: Int64? = nil, dur: Double = 0, pos: Double = 0,
                    played: Bool = false, archived: Bool = false, fav: Bool = false, dl: Bool = false,
                    dlAt: Int64? = nil, size: Int64? = nil) -> CarPlayEpisodeInfo {
        CarPlayEpisodeInfo(id: id, title: title ?? id, feedTitle: "Feed", artwork: nil, pubDateEpochMs: date,
                           durationSeconds: dur, positionSeconds: pos, isPlayed: played, isArchived: archived,
                           isFavorite: fav, isDownloaded: dl, downloadedAtEpochMs: dlAt, byteSize: size)
    }

    func testTabsFollowAndroidAutoOrderAndFitCarPlayLimit() {
        XCTAssertEqual(CarPlayTab.allCases, [.queue, .downloads, .episodes, .subscriptions])
        XCTAssertLessThanOrEqual(CarPlayTab.allCases.count, 4)
    }

    func testItemLimit() {
        XCTAssertEqual(CarPlayParity.itemLimit(templateMax: 500), 100)
        XCTAssertEqual(CarPlayParity.itemLimit(templateMax: 12), 12)
        XCTAssertEqual(CarPlayParity.itemLimit(templateMax: 0), 100)
    }

    func testProgress() {
        XCTAssertEqual(CarPlayParity.progress(ep("a", dur: 100, pos: 25)), 0.25, accuracy: 1e-9)
        XCTAssertEqual(CarPlayParity.progress(ep("a", dur: 100, pos: 250)), 1)
        XCTAssertEqual(CarPlayParity.progress(ep("a", dur: 0, pos: 25)), 0)
        XCTAssertEqual(CarPlayParity.progress(ep("a", dur: 100, played: true)), 1)
        XCTAssertTrue(CarPlayParity.isInProgress(ep("a", pos: 1)))
        XCTAssertFalse(CarPlayParity.isInProgress(ep("a", pos: 1, played: true)))
    }

    func testDetailShowsDurationOrFeed() {
        XCTAssertEqual(CarPlayParity.detail(ep("a", dur: 65)), "Feed · 1:05")
        XCTAssertNil(CarPlayParity.detail(ep("a"), showFeed: false))
    }

    func testEpisodesFilters() {
        let all = [ep("a", played: true), ep("b", archived: true), ep("c", fav: true), ep("d", dl: true)]
        func ids(_ f: AllEpisodesFilter) -> [String] {
            CarPlayParity.episodes(all, filter: f, sort: .titleAscending, limit: 100).map(\.id)
        }
        XCTAssertEqual(ids(.all), ["a", "b", "c", "d"])
        XCTAssertEqual(ids(.unplayed), ["c", "d"])
        XCTAssertEqual(ids(.favorites), ["c"])
        XCTAssertEqual(ids(.downloaded), ["d"])
    }

    func testEpisodesSorts() {
        let all = [ep("a", date: 1, dur: 30), ep("b", date: 3, dur: 0), ep("c", date: nil, dur: 10), ep("d", date: 2, dur: 20)]
        func ids(_ s: AllEpisodesSort) -> [String] { CarPlayParity.sorted(all, by: s).map(\.id) }
        XCTAssertEqual(ids(.newestFirst), ["b", "d", "a", "c"])
        XCTAssertEqual(ids(.oldestFirst), ["a", "d", "b", "c"])
        XCTAssertEqual(ids(.shortestFirst), ["c", "d", "a", "b"])
        XCTAssertEqual(ids(.longestFirst), ["a", "d", "c", "b"])
        XCTAssertEqual(ids(.titleDescending), ["d", "c", "b", "a"])
    }

    func testEpisodesLimit() {
        let all = (0..<150).map { ep("e\($0)", date: Int64($0)) }
        XCTAssertEqual(CarPlayParity.episodes(all, filter: .all, sort: .newestFirst, limit: 100).count, 100)
    }

    func testTitleOrderPutsEmptyLast() {
        XCTAssertEqual(CarPlayParity.titleOrder("", "b", ascending: true), false)
        XCTAssertEqual(CarPlayParity.titleOrder("a", "", ascending: false), true)
        XCTAssertNil(CarPlayParity.titleOrder("A", "a", ascending: true))
    }

    func testDownloadsSortAndFilter() {
        let all = [ep("a", date: 5, dl: true, dlAt: 10, size: 300), ep("b", date: 50, dl: true, size: nil),
                   ep("c", date: 1, dl: true, dlAt: 20, size: 100), ep("x", date: 99)]
        func ids(_ s: DownloadsSort) -> [String] { CarPlayParity.downloads(all, sort: s, limit: 100).map(\.id) }
        XCTAssertEqual(ids(.newestFirst), ["b", "c", "a"])
        XCTAssertEqual(ids(.oldestFirst), ["a", "c", "b"])
        XCTAssertEqual(ids(.largestFirst), ["a", "c", "b"])
        XCTAssertEqual(ids(.smallestFirst), ["c", "a", "b"])
    }

    func testFeedsSort() {
        let u1 = UUID(), u2 = UUID(), u3 = UUID()
        let feeds = [
            CarPlayParity.FeedInfo(id: u1, title: "Zeta", author: "Amy", unplayedCount: 1, lastRefreshedEpochMs: 5),
            CarPlayParity.FeedInfo(id: u2, title: "alpha", author: "Zed", unplayedCount: 9, lastRefreshedEpochMs: nil),
            CarPlayParity.FeedInfo(id: u3, title: "Mid", author: nil, unplayedCount: 1, lastRefreshedEpochMs: 7),
        ]
        func ids(_ s: SubscriptionsSort) -> [UUID] { CarPlayParity.feeds(feeds, sort: s, limit: 100).map(\.id) }
        XCTAssertEqual(ids(.alphabetical), [u2, u3, u1])
        XCTAssertEqual(ids(.mostUnplayed), [u2, u3, u1])
        XCTAssertEqual(ids(.recentlyRefreshed), [u3, u1, u2])
        XCTAssertEqual(ids(.leastRecentlyRefreshed), [u1, u3, u2])
        XCTAssertEqual(ids(.byAuthor), [u1, u2, u3])
    }
}

final class CarPlayFeedEpisodeParityTests: XCTestCase {
    private func ep(_ id: String, date: Int64?, dur: Double = 0, played: Bool = false, archived: Bool = false) -> CarPlayEpisodeInfo {
        CarPlayEpisodeInfo(id: id, title: id, feedTitle: "F", artwork: nil, pubDateEpochMs: date,
                           durationSeconds: dur, isPlayed: played, isArchived: archived)
    }

    func testSortMappingCoversAllCases() {
        for s in FeedEpisodeSort.allCases {
            XCTAssertEqual(CarPlayParity.allEpisodesSort(s).rawValue, s.rawValue)
        }
    }

    func testPerPodcastSortAndFilter() {
        let list = [ep("a", date: 1, dur: 30), ep("b", date: 3, played: true), ep("c", date: 2, dur: 10, archived: true)]
        func ids(_ s: FeedEpisodeSort, _ f: FeedEpisodeFilter) -> [String] {
            CarPlayParity.feedEpisodes(list, sort: s, filter: f, limit: 100).map(\.id)
        }
        XCTAssertEqual(ids(.newestFirst, .all), ["b", "c", "a"])
        XCTAssertEqual(ids(.oldestFirst, .all), ["a", "c", "b"])
        XCTAssertEqual(ids(.shortestFirst, .all), ["c", "a", "b"])
        XCTAssertEqual(ids(.newestFirst, .unplayed), ["a"])
        XCTAssertEqual(ids(.newestFirst, .played), ["b"])
    }

    func testPerPodcastOverrideBeatsGlobal() {
        var fs = FeedSettings.default
        XCTAssertEqual(fs.resolvedEpisodeSort(global: .newestFirst), .newestFirst)
        fs.episodeSort = .oldestFirst
        XCTAssertEqual(fs.resolvedEpisodeSort(global: .newestFirst), .oldestFirst)
    }

    func testLimit() {
        let list = (0..<120).map { ep("e\($0)", date: Int64($0)) }
        XCTAssertEqual(CarPlayParity.feedEpisodes(list, sort: .newestFirst, filter: .all, limit: 100).first?.id, "e119")
        XCTAssertEqual(CarPlayParity.feedEpisodes(list, sort: .newestFirst, filter: .all, limit: 100).count, 100)
    }
}
