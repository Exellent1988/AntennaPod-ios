import XCTest
@testable import AntennaPod

/// Duplicate / missing subscriptions after a gpodder import (beta a9539a179 device report).
/// Android reference: UrlChecker.urlEquals, SyncService.syncSubscriptions (redirect checks,
/// "Unknown podcast" placeholder for every added URL).
@MainActor
final class FeedDedupeTests: XCTestCase {
    private func feed(_ url: String, episodes: [String] = [], alternates: [String]? = nil, error: String? = nil) -> PodcastFeed {
        var f = PodcastFeed(
            id: UUID(), title: url, feedUrl: url, siteLink: nil, imageUrl: nil, descriptionText: nil,
            author: nil, language: nil, fundingUrl: nil, fundingLabel: nil, categories: [], isLocked: false,
            lockedOwner: nil, podcastGuid: nil,
            episodes: episodes.map { PodcastEpisode(id: $0, title: $0, downloadUrl: "https://e/\($0).mp3",
                                                    mimeType: "audio/mpeg", durationSeconds: 60) })
        f.alternateUrls = alternates
        f.loadError = error
        return f
    }

    // MARK: URL key (Android UrlChecker.urlEquals)

    func testKeyTreatsSchemeHostCaseSlashesAndDefaultPortAsEqual() {
        let k = FeedURLKey.key("https://feeds.example.com/show/mp3")
        for variant in ["http://feeds.example.com/show/mp3", "https://FEEDS.example.com/show/mp3/",
                        "  https://feeds.example.com//show/mp3  ", "https://feeds.example.com:443/show/mp3",
                        "http://feeds.example.com:80/Show/MP3", "feed://feeds.example.com/show/mp3",
                        "itpc://feeds.example.com/show/mp3", "https://feeds.example.com/show/mp3#top"] {
            XCTAssertEqual(FeedURLKey.key(variant), k, variant)
        }
    }

    func testKeyKeepsQueryPortAndHostDifferences() {
        XCTAssertNotEqual(FeedURLKey.key("https://e.com/feed?token=A"), FeedURLKey.key("https://e.com/feed?token=a"))
        XCTAssertNotEqual(FeedURLKey.key("https://e.com/feed"), FeedURLKey.key("https://e.com/feed?x=1"))
        XCTAssertNotEqual(FeedURLKey.key("https://e.com:8443/feed"), FeedURLKey.key("https://e.com/feed"))
        XCTAssertNotEqual(FeedURLKey.key("https://www.e.com/feed"), FeedURLKey.key("https://e.com/feed"))
        XCTAssertEqual(GpodderSyncService.normalizeFeedURL("HTTP://E.com/Feed/"), FeedURLKey.key("https://e.com/feed"))
    }

    // MARK: gpodder import

    func testImportSkipsSchemeVariantsAndKnownRedirectSources() {
        let todo = GpodderSyncLogic.urlsToImport(
            remote: ["http://a.example/feed", "https://a.example/feed/", "https://b.example/rss",
                     "https://old.example/podcast.xml", "https://c.example/rss"],
            localFeedURLs: feed("https://new.example/feed.xml", alternates: ["https://old.example/podcast.xml"]).allUrls
                + ["http://c.example/rss/"])
        XCTAssertEqual(todo, ["http://a.example/feed", "https://b.example/rss"])
    }

    func testRemoteRemoveMatchesAnyAddressOfTheFeed() {
        let local = feed("https://new.example/feed.xml", alternates: ["http://old.example/podcast.xml"])
        let urls = GpodderSyncLogic.feedsToUnsubscribe(remove: ["https://old.example/podcast.xml"], add: [],
                                                       localFeedURLs: local.allUrls)
        XCTAssertFalse(Set(urls.map(FeedURLKey.key)).isDisjoint(with: local.urlKeys))
    }

    // MARK: Merge on load

    func testMergeKeepsHttpsEntryUnionsEpisodesAndRecordsAlternates() {
        let http = feed("http://a.example/feed/", episodes: ["1", "2"])
        let https = feed("https://a.example/feed", episodes: ["2", "3"])
        let other = feed("https://b.example/rss", episodes: ["9"])
        let redirected = feed("https://short.example/x", episodes: ["4"], alternates: ["https://b.example/rss"])
        let result = FeedLibraryDedupe.merge([http, other, https, redirected])
        XCTAssertEqual(result.feeds.count, 2)
        let a = try! XCTUnwrap(result.feeds.first { $0.urlKeys.contains(FeedURLKey.key("https://a.example/feed")) })
        XCTAssertEqual(a.id, https.id, "https survives")
        XCTAssertEqual(Set(a.episodes.map(\.id)), ["1", "2", "3"])
        XCTAssertEqual(result.merged[http.id], https.id)
        XCTAssertEqual(result.merged[redirected.id], other.id, "same podcast through a redirect alias")
        XCTAssertEqual(result.feeds.map(\.id), [other.id, https.id], "library order of the survivors")
    }

    func testMergePrefersLoadedFeedOverPlaceholder() {
        let placeholder = feed("https://a.example/feed", error: "HTTP 500")
        let loaded = feed("http://a.example/feed", episodes: ["1"])
        let result = FeedLibraryDedupe.merge([placeholder, loaded])
        XCTAssertEqual(result.feeds.map(\.id), [loaded.id])
    }

    /// Crash-safety: one feed repeating a guid must not reach SwiftUI lists with duplicate ids.
    func testUniqueEpisodesDropsRepeatedIds() {
        let f = feed("https://a.example/feed", episodes: ["1", "2", "1", "3", "2"])
        XCTAssertEqual(PodcastFeed.uniqueEpisodes(f.episodes).map(\.id), ["1", "2", "3"])
    }

    func testStoreMergesDuplicatesAndMovesSettingsAndTags() {
        let store = PodcastStore()
        let saved = (store.feeds, store.feedSettingsById, store.tagsByFeedId)
        defer { store.feeds = saved.0; store.feedSettingsById = saved.1; store.tagsByFeedId = saved.2 }
        let http = feed("http://dup-\(UUID().uuidString).example/feed/", episodes: ["d1", "d1", "d2"])
        let https = feed(http.feedUrl.replacingOccurrences(of: "http://", with: "https://"), episodes: ["d2", "d3"])
        store.feeds = [http, https]
        store.tagsByFeedId = [http.id: ["News"]]
        store.mergeDuplicateFeeds()
        XCTAssertEqual(store.feeds.count, 1)
        XCTAssertEqual(store.feeds[0].id, https.id)
        XCTAssertEqual(store.feeds[0].episodes.map(\.id).sorted(), ["d1", "d2", "d3"])
        XCTAssertEqual(store.tagsByFeedId[https.id], ["News"])
        XCTAssertNil(store.tagsByFeedId[http.id])
    }

    // MARK: Missing podcasts

    func testFailedImportStaysAsPlaceholderAndIsNotDuplicated() {
        let store = PodcastStore()
        let saved = store.feeds
        defer { store.feeds = saved }
        store.feeds = []
        let url = "https://broken-\(UUID().uuidString).example/feed"
        let p = store.addPlaceholderFeed(url: url, error: "HTTP 404")
        XCTAssertEqual(store.feeds.count, 1)
        XCTAssertEqual(p?.loadError, "HTTP 404")
        store.addPlaceholderFeed(url: url.replacingOccurrences(of: "https", with: "http") + "/", error: "timeout")
        XCTAssertEqual(store.feeds.count, 1, "same podcast, no second placeholder")
        XCTAssertEqual(store.feeds[0].loadError, "timeout")
    }

    // MARK: Reset app data

    func testResetAppDataClearsLibraryButKeepsSettings() {
        let store = PodcastStore()
        let saved = (store.feeds, store.queue, store.playbackStates, store.favoriteAtById, store.tagsByFeedId,
                     store.feedSettingsById, store.archivedAtById, store.bookmarksByEpisodeId, store.episodePrivateNotesById)
        let savedQueue = store.gpodderActionQueue
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("reset-\(UUID().uuidString).json")
        store.gpodderActionQueue = GpodderActionQueue(fileURL: tmp)
        defer {
            store.feeds = saved.0; store.queue = saved.1; store.playbackStates = saved.2; store.favoriteAtById = saved.3
            store.tagsByFeedId = saved.4; store.feedSettingsById = saved.5; store.archivedAtById = saved.6
            store.bookmarksByEpisodeId = saved.7; store.episodePrivateNotesById = saved.8
            store.gpodderActionQueue = savedQueue
            try? FileManager.default.removeItem(at: tmp)
        }
        let f = feed("https://reset.example/feed", episodes: ["r1"])
        store.feeds = [f]
        store.queue = f.episodes
        store.favoriteAtById = ["r1": 1]
        store.tagsByFeedId = [f.id: ["X"]]
        store.gpodderActionQueue.enqueue(GpodderEpisodeAction(podcast: f.feedUrl, episode: "https://e/r1.mp3", guid: "r1",
                                                              action: "play", timestamp: nil, started: 0, position: 5,
                                                              total: 60, device: "d"))
        store.resetAppData()
        XCTAssertTrue(store.feeds.isEmpty)
        XCTAssertTrue(store.queue.isEmpty)
        XCTAssertTrue(store.favoriteAtById.isEmpty)
        XCTAssertTrue(store.tagsByFeedId.isEmpty)
        XCTAssertTrue(store.playbackStates.isEmpty)
        XCTAssertTrue(store.gpodderActionQueue.isEmpty)
    }
}
