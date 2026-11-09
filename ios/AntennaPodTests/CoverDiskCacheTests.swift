import PodcastCore
import XCTest
@testable import AntennaPod

/// Cover disk cache (Android prefImageCacheSize / Glide disk cache) + Images Wi‑Fi only.
@MainActor
final class CoverDiskCacheTests: PlaybackFixtureTestCase {
    private var dir: URL!
    private var cache: CoverDiskCache!
    private var fetches = 0

    override func setUp() async throws {
        try await super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("covers-\(UUID().uuidString)")
        cache = CoverDiskCache(directory: dir, limitBytes: 1_000)
        cache.fetchOverride = { [unowned self] url in
            self.fetches += 1
            return Data(repeating: UInt8(url.absoluteString.count % 255), count: 400)
        }
    }

    override func tearDown() async throws {
        MobileDataGate.pathOverrideForTests = nil
        try? FileManager.default.removeItem(at: dir)
        try await super.tearDown()
    }

    private func url(_ n: Int) -> URL { URL(string: "https://covers.example/\(n).jpg")! }

    func testSizeLimitEvictsLeastRecentlyUsed() async throws {
        MobileDataGate.pathOverrideForTests = (offline: false, unmetered: true)
        _ = try await cache.data(for: url(1), settings: settings)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -100)], ofItemAtPath: cache.fileURL(for: url(1)).path)
        _ = try await cache.data(for: url(2), settings: settings)
        _ = try await cache.data(for: url(3), settings: settings)
        XCTAssertLessThanOrEqual(cache.usageBytes, 1_000)
        XCTAssertNil(cache.cachedData(for: url(1)), "oldest evicted")
        XCTAssertNotNil(cache.cachedData(for: url(3)))
    }

    func testMobileDataWithImagesWifiOnlyServesDiskHitsAndFetchesNothingNew() async throws {
        MobileDataGate.pathOverrideForTests = (offline: false, unmetered: true)
        _ = try await cache.data(for: url(1), settings: settings)
        XCTAssertEqual(fetches, 1)
        settings.imagesWifiOnly = true
        MobileDataGate.pathOverrideForTests = (offline: false, unmetered: false)
        let hit = try await cache.data(for: url(1), settings: settings)
        XCTAssertEqual(hit.count, 400, "disk hit on mobile data")
        do {
            _ = try await cache.data(for: url(2), settings: settings)
            XCTFail("must not fetch over mobile data")
        } catch {}
        XCTAssertEqual(fetches, 1)
        MobileDataGate.pathOverrideForTests = (offline: true, unmetered: false)
        settings.imagesWifiOnly = false
        let offlineHit = try await cache.data(for: url(1), settings: settings)
        XCTAssertEqual(offlineHit.count, 400, "disk hit offline")
    }

    func testClearAndSettingInBackup() async throws {
        MobileDataGate.pathOverrideForTests = (offline: false, unmetered: true)
        _ = try await cache.data(for: url(1), settings: settings)
        XCTAssertGreaterThan(cache.usageBytes, 0)
        cache.clear()
        XCTAssertEqual(cache.usageBytes, 0)
        settings.imageCacheSizeMB = 250
        XCTAssertEqual(AppSettings().imageCacheSizeMB, 250)
        settings.imageCacheSizeMB = 33
        XCTAssertEqual(settings.imageCacheSizeMB, 100, "non-Android value → default")
        settings.imageCacheSizeMB = 50
        let data = try JSONEncoder().encode(settings.backupSnapshot())
        settings.imageCacheSizeMB = 500
        settings.applyBackupSnapshot(try JSONDecoder().decode(AppSettingsBackupSnapshot.self, from: data))
        XCTAssertEqual(settings.imageCacheSizeMB, 50)
    }
}
