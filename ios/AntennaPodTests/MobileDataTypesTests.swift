import PodcastCore
import XCTest
@testable import AntennaPod

/// Android prefMobileUpdateTypes folded into AppSettings + MobileDataGate (refresh, images).
@MainActor
final class MobileDataTypesTests: PlaybackFixtureTestCase {
    private var savedLog: [String]?

    override func setUp() async throws {
        try await super.setUp()
        savedLog = UserDefaults.standard.stringArray(forKey: AppMaintenanceLog.defaultsKey)
    }

    override func tearDown() async throws {
        MobileDataGate.pathOverrideForTests = nil
        store.mobileRefreshPrompt = false
        if let savedLog { UserDefaults.standard.set(savedLog, forKey: AppMaintenanceLog.defaultsKey) }
        else { UserDefaults.standard.removeObject(forKey: AppMaintenanceLog.defaultsKey) }
        try await super.tearDown()
    }

    func testMigrationFromLegacyWifiOnlyKeys() {
        let ud = UserDefaults(suiteName: "MobileDataTypesTests-\(UUID().uuidString)")!
        XCTAssertEqual(AppSettings.loadMobileUpdateTypes(ud), [.feedRefresh, .images, .episodeDownload, .streaming],
                       "never-set legacy keys = previous iOS defaults")
        ud.set(false, forKey: "settings.autoDownload.wifiOnly")
        ud.set(true, forKey: "settings.manualDownload.wifiOnly")
        ud.set(true, forKey: "settings.stream.wifiOnly")
        XCTAssertEqual(AppSettings.loadMobileUpdateTypes(ud), [.feedRefresh, .images, .autoDownload])
        ud.set(["images"], forKey: MobileUpdateTypes.defaultsKey)
        XCTAssertEqual(AppSettings.loadMobileUpdateTypes(ud), [.images], "stored list wins")
    }

    func testWifiOnlyTogglesAreViewsOfTheSetAndLegacyKeysStayInSync() {
        settings.mobileUpdateTypes = [.images]
        XCTAssertTrue(settings.autoDownloadWifiOnly)
        XCTAssertTrue(settings.manualDownloadWifiOnly)
        XCTAssertTrue(settings.streamWifiOnly)
        XCTAssertTrue(settings.feedRefreshWifiOnly)
        XCTAssertFalse(settings.imagesWifiOnly)
        settings.streamWifiOnly = false
        settings.imagesWifiOnly = true
        XCTAssertEqual(settings.mobileUpdateTypes, [.streaming])
        XCTAssertEqual(UserDefaults.standard.stringArray(forKey: MobileUpdateTypes.defaultsKey), ["streaming"])
        XCTAssertEqual(UserDefaults.standard.object(forKey: "settings.stream.wifiOnly") as? Bool, false)
        XCTAssertEqual(UserDefaults.standard.object(forKey: "settings.autoDownload.wifiOnly") as? Bool, true)
        XCTAssertEqual(AppSettings().mobileUpdateTypes, [.streaming], "persisted")
    }

    func testBackupRoundTripAndOlderBackup() throws {
        settings.mobileUpdateTypes = [.feedRefresh, .autoDownload]
        let data = try JSONEncoder().encode(settings.backupSnapshot())
        settings.mobileUpdateTypes = []
        settings.applyBackupSnapshot(try JSONDecoder().decode(AppSettingsBackupSnapshot.self, from: data))
        XCTAssertEqual(settings.mobileUpdateTypes, [.feedRefresh, .autoDownload])
        var old = settings.backupSnapshot()
        old.mobileUpdateTypes = nil
        old.streamWifiOnly = false
        settings.imagesWifiOnly = true
        settings.applyBackupSnapshot(old)
        XCTAssertFalse(settings.streamWifiOnly, "older backup: legacy flags apply")
        XCTAssertTrue(settings.imagesWifiOnly, "older backup leaves images alone")
    }

    func testFeedRefreshOnMobileAsksWhenUserStartedAndSkipsWhenAutomatic() async {
        MobileDataGate.pathOverrideForTests = (offline: false, unmetered: false)
        settings.feedRefreshWifiOnly = true
        await store.refreshAllFeeds(userInitiated: false)
        XCTAssertFalse(store.mobileRefreshPrompt)
        XCTAssertTrue(AppMaintenanceLog.entries().last?.contains("feed refresh: skipped on mobile data") == true)
        await store.refreshAllFeeds()
        XCTAssertTrue(store.mobileRefreshPrompt, "manual refresh asks (Refresh anyway / Always allow / Cancel)")
    }

    func testImageRequestIsCacheOnlyOnMobileWhenImagesOff() {
        let url = URL(string: "https://img.example/cover.jpg")!
        settings.imagesWifiOnly = true
        MobileDataGate.pathOverrideForTests = (offline: false, unmetered: false)
        XCTAssertEqual(MobileDataGate.imageRequest(for: url, settings: settings).cachePolicy, .returnCacheDataDontLoad)
        MobileDataGate.pathOverrideForTests = (offline: false, unmetered: true)
        XCTAssertEqual(MobileDataGate.imageRequest(for: url, settings: settings).cachePolicy, .useProtocolCachePolicy, "Wi‑Fi loads")
        settings.imagesWifiOnly = false
        MobileDataGate.pathOverrideForTests = (offline: false, unmetered: false)
        XCTAssertEqual(MobileDataGate.imageRequest(for: url, settings: settings).cachePolicy, .useProtocolCachePolicy, "images allowed on mobile")
    }
}
