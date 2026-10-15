import PodcastCore
import XCTest
@testable import AntennaPod

/// Enqueue downloaded default: on for new installs, off for existing installs, stored value kept.
/// Runs on a private UserDefaults suite, so `UserDefaults.standard` (leak check) is untouched.
@MainActor
final class EnqueueDownloadedMigrationTests: XCTestCase {
    private var suiteName = ""
    private var ud: UserDefaults!
    private let key = "settings.enqueueDownloaded"

    override func setUp() async throws {
        suiteName = "EnqueueDownloadedMigrationTests-\(UUID().uuidString)"
        ud = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        ud.removePersistentDomain(forName: suiteName)
        ud = nil
    }

    func testFreshInstallGetsOn() {
        let existing = AppSettings.hasExistingAppData(ud, hasStoredFeeds: false)
        XCTAssertFalse(existing)
        AppSettings.migrateEnqueueDownloadedDefault(ud, hasExistingData: existing)
        XCTAssertEqual(ud.object(forKey: key) as? Bool, true)
    }

    func testExistingDataWithoutKeyGetsOff() {
        // Library on disk.
        XCTAssertTrue(AppSettings.hasExistingAppData(ud, hasStoredFeeds: true))
        // Older settings keys only.
        ud.set(1.5, forKey: "settings.defaultPlaybackSpeed")
        let existing = AppSettings.hasExistingAppData(ud, hasStoredFeeds: false)
        XCTAssertTrue(existing)
        AppSettings.migrateEnqueueDownloadedDefault(ud, hasExistingData: existing)
        XCTAssertEqual(ud.object(forKey: key) as? Bool, false)
    }

    func testExistingKeyIsNotOverwritten() {
        ud.set(true, forKey: key)
        AppSettings.migrateEnqueueDownloadedDefault(ud, hasExistingData: true)
        XCTAssertEqual(ud.object(forKey: key) as? Bool, true)
        ud.set(false, forKey: key)
        AppSettings.migrateEnqueueDownloadedDefault(ud, hasExistingData: false)
        XCTAssertEqual(ud.object(forKey: key) as? Bool, false)
        // The key alone doesn't count as existing data.
        XCTAssertFalse(AppSettings.hasExistingAppData(ud, hasStoredFeeds: false))
    }
}
