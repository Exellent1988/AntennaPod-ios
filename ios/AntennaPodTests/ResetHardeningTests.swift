import PodcastCore
import XCTest
@testable import AntennaPod

/// Settings → Reset app data, hardened order: stop playback + audio session, cancel downloads and
/// wait for the background session, delete local data, log it; then a gpodder re-import.
@MainActor
final class ResetHardeningTests: PlaybackFixtureTestCase {
    private typealias StoreSnapshot = ([PodcastFeed], [String: Int64], [String: Int64], [String: [EpisodeBookmark]],
                                       [String: String], [UUID: [String]], [UUID: FeedSettings])
    private var storeSnapshot: StoreSnapshot!
    private var savedActionQueue: GpodderActionQueue!
    private var savedGpodder: [String: Any] = [:]
    private var savedLog: [String]?
    private let gpodderKeys = ["gpodder.provider", "gpodder.host", "gpodder.username", "gpodder.deviceId",
                               "gpodder.deviceName", "gpodder.isLoggedIn"]

    override func setUp() async throws {
        try await super.setUp()
        storeSnapshot = (store.feeds, store.favoriteAtById, store.archivedAtById, store.bookmarksByEpisodeId,
                         store.episodePrivateNotesById, store.tagsByFeedId, store.feedSettingsById)
        savedActionQueue = store.gpodderActionQueue
        store.gpodderActionQueue = GpodderActionQueue(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("reset-hard-\(UUID().uuidString).json"))
        for k in gpodderKeys { savedGpodder[k] = UserDefaults.standard.object(forKey: k) }
        savedLog = UserDefaults.standard.stringArray(forKey: AppMaintenanceLog.defaultsKey)
    }

    override func tearDown() async throws {
        store.feeds = storeSnapshot.0; store.favoriteAtById = storeSnapshot.1; store.archivedAtById = storeSnapshot.2
        store.bookmarksByEpisodeId = storeSnapshot.3; store.episodePrivateNotesById = storeSnapshot.4
        store.tagsByFeedId = storeSnapshot.5; store.feedSettingsById = storeSnapshot.6
        store.gpodderActionQueue = savedActionQueue
        for k in gpodderKeys {
            if let v = savedGpodder[k] { UserDefaults.standard.set(v, forKey: k) }
            else { UserDefaults.standard.removeObject(forKey: k) }
        }
        if let savedLog { UserDefaults.standard.set(savedLog, forKey: AppMaintenanceLog.defaultsKey) }
        else { UserDefaults.standard.removeObject(forKey: AppMaintenanceLog.defaultsKey) }
        try await super.tearDown()
    }

    private nonisolated static func makeFeed(_ url: String, episodes: [String] = ["e"]) -> PodcastFeed {
        PodcastFeed(id: UUID(), title: url, feedUrl: url, siteLink: nil, imageUrl: nil, descriptionText: nil,
                    author: nil, language: nil, fundingUrl: nil, fundingLabel: nil, categories: [], isLocked: false,
                    lockedOwner: nil, podcastGuid: nil,
                    episodes: episodes.map { PodcastEpisode(id: "\(url)#\($0)", title: $0, downloadUrl: "https://e/\($0).mp3",
                                                            mimeType: "audio/mpeg", durationSeconds: 60) })
    }

    func testResetStopsPlaybackClearsLibraryKeepsLoginSettingsAndPlayerOptions() async throws {
        // Login (non-secret parts; the password lives in the Keychain and is never touched).
        let login: [String: Any] = ["gpodder.provider": "gpodder", "gpodder.host": "https://gpodder.example",
                                    "gpodder.username": "reset-test", "gpodder.deviceId": "ios-reset-test",
                                    "gpodder.deviceName": "Reset Test", "gpodder.isLoggedIn": true]
        for (k, v) in login { UserDefaults.standard.set(v, forKey: k) }
        // Player options + other app settings.
        settings.defaultPlaybackSpeed = 1.6
        settings.skipSilenceEnabled = true
        settings.skipIntroSeconds = 7
        settings.remainingTimeRespectsSpeed = true
        // Library.
        let f = Self.makeFeed("https://reset-hard.example/feed", episodes: ["a", "b"])
        store.feeds = [f]
        store.favoriteAtById = [f.episodes[0].id: 1]
        store.tagsByFeedId = [f.id: ["T"]]
        XCTAssertTrue(playback.play(episode: episodes[0]))
        try await waitFor("playing", timeout: 5) { self.playback.isPlaying }
        XCTAssertEqual(playback.isOutputMutedForTests, true)

        let report = await store.resetAppDataSafely(downloadDrainTimeout: 2)

        XCTAssertTrue(report.stoppedPlayback)
        XCTAssertEqual(report.feedsBefore, 1)
        XCTAssertNil(playback.currentEpisode)
        XCTAssertFalse(playback.isPlaying)
        XCTAssertFalse(playback.hasLoadedPlayerForTests, "player torn down before the catalog is deleted")
        XCTAssertTrue(store.feeds.isEmpty)
        XCTAssertTrue(store.queue.isEmpty)
        XCTAssertTrue(store.playbackStates.isEmpty)
        XCTAssertTrue(store.favoriteAtById.isEmpty)
        XCTAssertTrue(store.tagsByFeedId.isEmpty)
        XCTAssertTrue(store.feedSettingsById.isEmpty)
        for (k, v) in login {
            XCTAssertEqual(UserDefaults.standard.object(forKey: k) as? NSObject, v as? NSObject, "\(k) kept")
        }
        let reloaded = AppSettings()
        XCTAssertEqual(reloaded.defaultPlaybackSpeed, 1.6, accuracy: 0.001, "player speed kept")
        XCTAssertTrue(reloaded.skipSilenceEnabled, "skip silence kept")
        XCTAssertEqual(reloaded.skipIntroSeconds, 7, "skip intro kept")
        XCTAssertTrue(reloaded.remainingTimeRespectsSpeed, "app setting kept")
        let log = AppMaintenanceLog.entries()
        XCTAssertTrue(log.contains { $0.hasSuffix("reset: start (feeds 1, queue 3)") }, "\(log.suffix(3))")
        XCTAssertTrue(log.contains { $0.contains("reset: playback stopped true") })
        XCTAssertTrue(log.contains { $0.hasSuffix("reset: local data deleted (login and settings kept)") })
    }

    func testResetCancelsDownloadsAndWaitsForBackgroundSession() async throws {
        let downloads = try XCTUnwrap(AppServices.downloads, "test host app creates the DownloadService")
        let savedStore = downloads.store, savedSettings = downloads.settings
        downloads.store = store; downloads.settings = settings
        store.downloads = downloads
        settings.manualDownloadWifiOnly = false
        defer { downloads.store = savedStore; downloads.settings = savedSettings; store.downloads = nil }
        let remote = (1...2).map {
            PodcastEpisode(id: "reset-dl-\(UUID().uuidString.prefix(6))-\($0)", title: "R\($0)",
                           downloadUrl: "https://reset-hardening.invalid/r\($0).mp3", mimeType: "audio/mpeg", durationSeconds: 60)
        }
        for ep in remote { await downloads.download(ep) }
        XCTAssertTrue(remote.allSatisfy { downloads.inProgress.contains($0.id) })

        let report = await store.resetAppDataSafely(downloadDrainTimeout: 5)

        XCTAssertEqual(report.cancelledDownloads, 2)
        XCTAssertTrue(report.downloadsDrained, "background session had no live task left within the timeout")
        XCTAssertTrue(downloads.inProgress.isEmpty)
        XCTAssertFalse(downloads.isReplacingSession)
    }

    /// Reset, then the full gpodder import over the existing `GpodderSyncService.subscribeMissing`
    /// with the fake fetch used by GpodderImportCompletenessTests (no network, no gpodder changes).
    func testReimportAfterResetIsCompleteWithoutDuplicates() async {
        store.feeds = [Self.makeFeed("https://old-local.example/rss")]
        await store.resetAppDataSafely(downloadDrainTimeout: 1)
        XCTAssertTrue(store.feeds.isEmpty)

        let server = ["https://feeds.metaebene.me/lnp/mp3", "http://feeds.metaebene.me/lnp/mp3/",
                      "https://logbuch-netzpolitik.de/feed/mp3", "https://feeds.simplecast.com/54nAGcIl",
                      "http://FEEDS.simplecast.com/54nAGcIl/", "https://broken.example/rss",
                      "https://ok.example/a.xml", "ftp://ignored.example/rss"]
        let redirects = ["https://logbuch-netzpolitik.de/feed/mp3": "https://feeds.metaebene.me/lnp/mp3"]
        let store = self.store!
        let sync = GpodderSyncService()
        let result = await sync.subscribeMissing(server, store: store, subscribe: { url in
            if url == "https://broken.example/rss" { throw URLError(.badServerResponse) }
            await MainActor.run {
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
        })
        store.mergeDuplicateFeeds()

        // Complete: every http(s) server podcast is covered by exactly one library entry.
        let wanted = ["feeds.metaebene.me/lnp/mp3", "logbuch-netzpolitik.de/feed/mp3",
                      "feeds.simplecast.com/54nagcil", "broken.example/rss", "ok.example/a.xml"]
        for key in wanted {
            XCTAssertEqual(store.feeds.filter { $0.urlKeys.contains(key) }.count, 1, "\(key) imported exactly once")
        }
        XCTAssertFalse(store.feeds.contains { $0.feedUrl.hasPrefix("https://old-local") }, "nothing left from before the reset")
        XCTAssertNotNil(store.feeds.first { $0.feedUrl == "https://broken.example/rss" }?.loadError, "failed feed kept as placeholder")
        XCTAssertEqual(result.failures.map(\.url), ["https://broken.example/rss"])
        // No duplicates: 4 podcasts (logbuch redirects into lnp), no two entries share a URL key.
        XCTAssertEqual(store.feeds.count, 4)
        for (i, a) in store.feeds.enumerated() {
            for b in store.feeds[(i + 1)...] { XCTAssertTrue(a.urlKeys.isDisjoint(with: b.urlKeys), "\(a.feedUrl) vs \(b.feedUrl)") }
        }

        // Redirect pair: the parallel import may store either URL first (the app keeps the stored
        // feedUrl, the other becomes an alias), so check the fold, not which URL is primary.
        let lnp = store.feeds.filter { $0.urlKeys.contains("feeds.metaebene.me/lnp/mp3") }
        XCTAssertEqual(lnp.count, 1, "redirect pair is one podcast")
        XCTAssertTrue(lnp.first?.urlKeys.contains("logbuch-netzpolitik.de/feed/mp3") == true, "redirect source kept as alias")
    }
}
