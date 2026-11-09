import PodcastCore
import XCTest
@testable import AntennaPod

/// Android AutomaticDownloadAlgorithm (queue candidates), prefEnableAutoDownloadOnBattery and
/// "Edit feed URL" on the real store / settings / DownloadService. No network transfer starts.
@MainActor
final class AutoDownloadParityAppTests: PlaybackFixtureTestCase {
    private var savedFeeds: [PodcastFeed] = []
    private var feed: PodcastFeed!
    private var downloads: DownloadService!
    private var savedLog: [String]?

    override func setUp() async throws {
        try await super.setUp()
        savedFeeds = store.feeds
        savedLog = UserDefaults.standard.stringArray(forKey: AppMaintenanceLog.defaultsKey)
        downloads = try XCTUnwrap(AppServices.downloads)
        let run = UUID().uuidString.prefix(6)
        let eps = (1...3).map {
            PodcastEpisode(id: "adp-\(run)-\($0)", title: "ADP \($0)", downloadUrl: "https://adp.invalid/\(run)/\($0).mp3",
                           mimeType: "audio/mpeg", durationSeconds: 60)
        }
        feed = PodcastFeed(id: UUID(), title: "ADP", feedUrl: "https://adp.invalid/\(run)/rss", siteLink: nil, imageUrl: nil,
                           descriptionText: nil, author: nil, language: nil, fundingUrl: nil, fundingLabel: nil,
                           categories: [], isLocked: false, lockedOwner: nil, podcastGuid: nil, episodes: eps)
        store.feeds = savedFeeds + [feed]
    }

    override func tearDown() async throws {
        AutoDownloadCoordinator.powerStateOverrideForTests = nil
        store.setFeedSettings(.default, for: feed.id)
        store.feeds = savedFeeds
        if let savedLog { UserDefaults.standard.set(savedLog, forKey: AppMaintenanceLog.defaultsKey) }
        else { UserDefaults.standard.removeObject(forKey: AppMaintenanceLog.defaultsKey) }
        try await super.tearDown()
    }

    func testDownloadWhenNotChargingDefaultPersistedAndInBackup() throws {
        settings.autoDownloadOnBattery = false
        XCTAssertFalse(AppSettings().autoDownloadOnBattery)
        let data = try JSONEncoder().encode(settings.backupSnapshot())
        settings.autoDownloadOnBattery = true
        settings.applyBackupSnapshot(try JSONDecoder().decode(AppSettingsBackupSnapshot.self, from: data))
        XCTAssertFalse(settings.autoDownloadOnBattery)
        var old = settings.backupSnapshot(); old.autoDownloadOnBattery = nil
        settings.autoDownloadOnBattery = true
        settings.applyBackupSnapshot(old)
        XCTAssertTrue(settings.autoDownloadOnBattery, "older backup leaves it unchanged")
    }

    func testQueuedEpisodesAreAutoDownloadCandidates() {
        settings.autoDownloadEnabled = true
        store.queue = [feed.episodes[2], feed.episodes[0], episodes[0]]
        store.markPlayed(feed.episodes[1].id)
        var picked = AutoDownloadCoordinator.queuedAutoDownloadCandidates(store: store, downloads: downloads, settings: settings)
        XCTAssertEqual(picked.map(\.id), [feed.episodes[2].id, feed.episodes[0].id], "queue order; local fixture files skipped")
        store.updateFeedSettings(for: feed.id) { $0.autoDownload = .never }
        picked = AutoDownloadCoordinator.queuedAutoDownloadCandidates(store: store, downloads: downloads, settings: settings)
        XCTAssertTrue(picked.isEmpty, "per-podcast Never")
        settings.autoDownloadEnabled = false
        store.updateFeedSettings(for: feed.id) { $0.autoDownload = .always }
        picked = AutoDownloadCoordinator.queuedAutoDownloadCandidates(store: store, downloads: downloads, settings: settings)
        XCTAssertEqual(picked.count, 2, "per-podcast Always beats global off")
        store.updateFeedSettings(for: feed.id) { $0.autoDownload = .useGlobal }
        XCTAssertTrue(AutoDownloadCoordinator.queuedAutoDownloadCandidates(store: store, downloads: downloads, settings: settings).isEmpty)
    }

    func testOnBatteryOffSkipsAutomaticDownloads() async {
        settings.autoDownloadEnabled = true
        settings.autoDownloadOnBattery = false
        AutoDownloadCoordinator.powerStateOverrideForTests = .unplugged
        store.queue = [feed.episodes[0]]
        let savedStore = downloads.store, savedSettings = downloads.settings
        downloads.store = store; downloads.settings = settings
        defer { downloads.store = savedStore; downloads.settings = savedSettings }
        await AutoDownloadCoordinator.enqueueAfterRefresh(store: store, downloads: downloads, settings: settings, newBatches: [])
        XCTAssertFalse(downloads.inProgress.contains(feed.episodes[0].id))
        XCTAssertTrue(AppMaintenanceLog.entries().last?.contains("skipped on battery") == true)
    }

    func testChangeFeedUrlKeepsEpisodesSettingsAndRejectsDuplicates() async {
        store.updateFeedSettings(for: feed.id) { $0.playbackSpeed = 1.3 }
        let newUrl = "https://adp-moved.invalid/\(UUID().uuidString.prefix(6))/rss"
        let r = await store.changeFeedUrl(feedId: feed.id, to: "  \(newUrl) ", refresh: false)
        XCTAssertEqual(r, .ok(newUrl))
        let moved = store.feeds.first { $0.id == feed.id }
        XCTAssertEqual(moved?.feedUrl, newUrl)
        XCTAssertEqual(moved?.episodes.count, 3, "episodes kept")
        XCTAssertEqual(store.feedSettings(for: feed.id).playbackSpeed, 1.3, "settings kept")
        if let other = savedFeeds.first {
            let dup = await store.changeFeedUrl(feedId: feed.id, to: other.feedUrl, refresh: false)
            XCTAssertEqual(dup, .duplicate)
        }
        XCTAssertTrue(moved?.urlKeys.contains(FeedURLKey.key(feed.feedUrl)) == true, "old URL kept as alias")
        let bad = await store.changeFeedUrl(feedId: feed.id, to: "ftp://x/rss", refresh: false)
        XCTAssertEqual(bad, .invalid)
        XCTAssertEqual(store.feeds.first { $0.id == feed.id }?.feedUrl, newUrl)
    }

    /// Feed URL edited while the gpodder server still lists the old address: the next pull imports
    /// nothing (no second podcast) and the push uploads nothing (old URL already on the server).
    func testChangedFeedUrlDoesNotDuplicateOrDoublePushWithGpodder() async {
        let oldUrl = feed.feedUrl
        let newUrl = "https://adp-new.invalid/\(UUID().uuidString.prefix(6))/rss"
        _ = await store.changeFeedUrl(feedId: feed.id, to: newUrl, refresh: false)
        let local = store.feeds.flatMap(\.allUrls)
        XCTAssertEqual(GpodderSyncLogic.urlsToImport(remote: [oldUrl], localFeedURLs: local), [],
                       "old URL on the server is not re-imported")
        XCTAssertEqual(SubscriptionSyncPlan.urlsToUpload(localPodcasts: store.feeds.filter { $0.id == feed.id }.map(\.allUrls),
                                                          remoteKeys: FeedURLEquality.keys([oldUrl])), [],
                       "new URL not pushed next to the old one")
        XCTAssertEqual(SubscriptionSyncPlan.podcastsToUnsubscribe(remove: [oldUrl], add: [newUrl],
                                                                  localPodcasts: [store.feeds.first { $0.id == feed.id }!.allUrls]), [],
                       "server-side rename (remove old + add new) keeps the podcast")
        // Changing back makes the old URL primary again, no stale alias of itself.
        _ = await store.changeFeedUrl(feedId: feed.id, to: oldUrl, refresh: false)
        let back = store.feeds.first { $0.id == feed.id }
        XCTAssertEqual(back?.feedUrl, oldUrl)
        XCTAssertEqual(back?.alternateUrls?.map(FeedURLKey.key).contains(FeedURLKey.key(oldUrl)), false)
        XCTAssertTrue(back?.urlKeys.contains(FeedURLKey.key(newUrl)) == true)
    }
}
