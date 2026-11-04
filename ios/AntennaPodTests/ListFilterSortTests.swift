import PodcastCore
import XCTest
@testable import AntennaPod

/// Android episode filter / sort parity: per-screen + per-feed options, Queue keep sorted.
@MainActor
final class ListFilterSortTests: PlaybackFixtureTestCase {
    private func makeFeed() -> PodcastFeed {
        let url = "https://list-filter.example/feed"
        let specs: [(String, Double, Int64)] = [("b", 300, 2), ("a", 100, 3), ("c", 200, 1)]
        return PodcastFeed(id: UUID(), title: "LF", feedUrl: url, siteLink: nil, imageUrl: nil, descriptionText: nil,
                           author: nil, language: nil, fundingUrl: nil, fundingLabel: nil, categories: [], isLocked: false,
                           lockedOwner: nil, podcastGuid: nil,
                           episodes: specs.map { s in
                               var e = PodcastEpisode(id: "\(url)#\(s.0)", title: s.0, downloadUrl: "https://e/\(s.0).mp3",
                                                      mimeType: "audio/mpeg", durationSeconds: s.1)
                               e.pubDateEpochMs = s.2
                               return e
                           })
    }

    func testFactsFromStore() {
        let f = makeFeed()
        store.feeds = [f]
        store.queue = [f.episodes[0]]
        store.saveProgress(episodeId: f.episodes[1].id, positionSeconds: 30, durationSeconds: 100)
        let q = store.listFacts(for: f.episodes[0]), p = store.listFacts(for: f.episodes[1])
        XCTAssertTrue(q.isQueued); XCTAssertFalse(p.isQueued)
        XCTAssertTrue(p.isPaused); XCTAssertTrue(q.hasMedia)
        XCTAssertEqual(q.feedTitle, store.displayTitle(for: f))
    }

    func testPerFeedOptionsPersistAndBackup() throws {
        let id = UUID()
        let o = EpisodeListOptions(filter: .init([.unplayed]), sort: .sizeLargeSmall)
        settings.setListOptions(o, forFeed: id)
        settings.allEpisodesListOptions = EpisodeListOptions(sort: .titleZA)
        XCTAssertEqual(AppSettings().listOptions(forFeed: id), o, "remembered per feed")
        XCTAssertEqual(AppSettings().allEpisodesListOptions.sort, .titleZA, "remembered per screen")
        XCTAssertEqual(settings.listOptions(forFeed: UUID()), EpisodeListOptions())
        let data = try JSONEncoder().encode(settings.backupSnapshot())
        settings.setListOptions(.init(), forFeed: id)
        settings.allEpisodesListOptions = .init()
        settings.applyBackupSnapshot(try JSONDecoder().decode(AppSettingsBackupSnapshot.self, from: data))
        XCTAssertEqual(settings.listOptions(forFeed: id), o)
        XCTAssertEqual(settings.allEpisodesListOptions.sort, .titleZA)
        settings.setListOptions(.init(), forFeed: id)
        XCTAssertNil(settings.feedListOptions[id.uuidString], "default options are not stored")
    }

    func testQueueKeepSorted() {
        let f = makeFeed()
        store.feeds = [f]
        store.queue = f.episodes
        XCTAssertEqual(store.queue.map(\.title), ["b", "a", "c"], "off: manual order")
        settings.queueKeepSortedOrder = .durationShortLong
        store.applyQueueKeepSorted()
        XCTAssertEqual(store.queue.map(\.title), ["a", "c", "b"])
        store.queue = [f.episodes[0], f.episodes[1]]
        store.queue.append(f.episodes[2])
        XCTAssertEqual(store.queue.map(\.title), ["a", "c", "b"], "stays sorted after changes")
        settings.queueKeepSortedOrder = nil
        store.queue = f.episodes
        XCTAssertEqual(store.queue.map(\.title), ["b", "a", "c"])
    }
}
