import PodcastCore
import XCTest
@testable import AntennaPod

/// Android prefEpisodeCleanup / prefEpisodeCacheSize / prefStreamOverDownload on the app side.
/// Migration cases run on a private UserDefaults suite (the leak check watches `.standard`).
@MainActor
final class CleanupStreamParityTests: XCTestCase {
    private var suiteName = ""
    private var ud: UserDefaults!

    override func setUp() async throws {
        suiteName = "CleanupStreamParityTests-\(UUID().uuidString)"
        ud = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        ud.removePersistentDomain(forName: suiteName)
        ud = nil
    }

    func testFreshInstallGetsAndroidDefaults() {
        AppSettings.migrateEpisodeCleanupDefaults(ud, hasExistingData: false)
        XCTAssertEqual(ud.object(forKey: "settings.downloadEpisodeCacheLimit") as? Int, 20)
        XCTAssertEqual(ud.object(forKey: "settings.episodeCleanup") as? Int, -2, "Never")
    }

    func testExistingInstallKeepsUnlimited() {
        AppSettings.migrateEpisodeCleanupDefaults(ud, hasExistingData: true)
        XCTAssertEqual(ud.object(forKey: "settings.downloadEpisodeCacheLimit") as? Int, 0)
        XCTAssertEqual(ud.object(forKey: "settings.episodeCleanup") as? Int, -2)
    }

    func testExistingLimitKeepsOldEvictionAndValues() {
        ud.set(50, forKey: "settings.downloadEpisodeCacheLimit")
        AppSettings.migrateEpisodeCleanupDefaults(ud, hasExistingData: true)
        XCTAssertEqual(ud.object(forKey: "settings.downloadEpisodeCacheLimit") as? Int, 50)
        XCTAssertEqual(ud.object(forKey: "settings.episodeCleanup") as? Int, -1, "When not in queue")
        ud.set(168, forKey: "settings.episodeCleanup")
        AppSettings.migrateEpisodeCleanupDefaults(ud, hasExistingData: true)
        XCTAssertEqual(ud.object(forKey: "settings.episodeCleanup") as? Int, 168, "stored value not overwritten")
    }

    func testMigrationKeysDoNotCountAsExistingData() {
        AppSettings.migrateEpisodeCleanupDefaults(ud, hasExistingData: false)
        XCTAssertFalse(AppSettings.hasExistingAppData(ud, hasStoredFeeds: false))
    }

    func testBackupRoundTripAndOldBackups() {
        let settings = AppSettings()
        let original = settings.backupSnapshot()
        defer {
            settings.applyBackupSnapshot(original)
            SettingsLeakObserver.restoreToTestStart()
        }
        settings.episodeCleanup = .afterFinishing(hours: 72)
        settings.streamOverDownload = true
        let snap = settings.backupSnapshot()
        XCTAssertEqual(snap.episodeCleanup, 72)
        XCTAssertEqual(snap.streamOverDownload, true)
        var old = snap
        old.episodeCleanup = nil; old.streamOverDownload = nil; old.downloadEpisodeCacheLimit = 50
        settings.applyBackupSnapshot(old)
        XCTAssertEqual(settings.episodeCleanup, .notInQueue, "old backup with a limit keeps the old eviction")
        XCTAssertFalse(settings.streamOverDownload)
        old.downloadEpisodeCacheLimit = 0
        settings.applyBackupSnapshot(old)
        XCTAssertEqual(settings.episodeCleanup, .never)
    }

    func testRowShowsStreamInsteadOfDownload() {
        XCTAssertTrue(EpisodeRow.showsDownloadButton(isDownloaded: false, isDownloading: false, streamOverDownload: false))
        XCTAssertFalse(EpisodeRow.showsDownloadButton(isDownloaded: false, isDownloading: false, streamOverDownload: true))
        XCTAssertTrue(EpisodeRow.showsDownloadButton(isDownloaded: false, isDownloading: true, streamOverDownload: true), "cancel stays")
        XCTAssertTrue(EpisodeRow.showsDownloadButton(isDownloaded: true, isDownloading: false, streamOverDownload: true), "Downloaded badge stays")
    }

    func testCleanupLabels() {
        XCTAssertEqual(SettingsView.episodeCleanupLabel(.afterFinishing(hours: 12)), String(format: String(localized: "%lld hours after finishing"), 12))
        XCTAssertEqual(SettingsView.episodeCleanupLabel(.afterFinishing(hours: 24)), String(localized: "1 day after finishing"))
        XCTAssertEqual(SettingsView.episodeCleanupLabel(.afterFinishing(hours: 168)), String(format: String(localized: "%lld days after finishing"), 7))
        XCTAssertEqual(DownloadEpisodeCacheLimit.allCases.first, .five)
    }
}
