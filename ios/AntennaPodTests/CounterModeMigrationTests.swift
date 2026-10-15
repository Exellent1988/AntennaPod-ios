import XCTest
@testable import AntennaPod

/// Android UserPreferences.getFeedCounterSetting default FeedCounter.SHOW_NEW: new installs and users who
/// never picked a mode (old implicit iOS default) move to Neu once; an explicit choice is kept.
@MainActor
final class CounterModeMigrationTests: XCTestCase {
    private let modeKey = "settings.subscriptionsCounterMode"
    private let flagKey = "settings.subscriptionsCounterModeDefaultMigrated"
    private var suiteName = ""
    private var ud: UserDefaults!

    override func setUp() async throws {
        suiteName = "CounterModeMigrationTests-\(UUID().uuidString)"
        ud = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        ud.removePersistentDomain(forName: suiteName)
        ud = nil
    }

    func testNewInstallGetsNew() {
        XCTAssertEqual(AppSettings.migrateCounterModeDefaultOnce(ud), .new)
        XCTAssertEqual(ud.string(forKey: modeKey), "new")
    }

    func testImplicitOldDefaultMovesToNew() {
        // Existing user who never touched the picker: nothing stored, old code showed .unplayed.
        ud.set("x", forKey: "settings.someOtherKey")
        XCTAssertEqual(AppSettings.migrateCounterModeDefaultOnce(ud), .new)
    }

    func testExplicitUnplayedStays() {
        ud.set("unplayed", forKey: modeKey)
        XCTAssertEqual(AppSettings.migrateCounterModeDefaultOnce(ud), .unplayed)
        XCTAssertEqual(ud.string(forKey: modeKey), "unplayed")
    }

    func testExplicitOtherModesStay() {
        for mode in ["none", "downloaded"] {
            ud.removeObject(forKey: flagKey)
            ud.set(mode, forKey: modeKey)
            XCTAssertEqual(AppSettings.migrateCounterModeDefaultOnce(ud).rawValue, mode)
        }
    }

    func testRunsOnlyOnce() {
        XCTAssertEqual(AppSettings.migrateCounterModeDefaultOnce(ud), .new)
        XCTAssertTrue(ud.bool(forKey: flagKey))
        // Later explicit choice, then a relaunch: not touched again.
        ud.set("unplayed", forKey: modeKey)
        XCTAssertEqual(AppSettings.migrateCounterModeDefaultOnce(ud), .unplayed)
        // Even if the value went missing after the migration, it doesn't re-run (falls back to Android's default).
        ud.removeObject(forKey: modeKey)
        XCTAssertEqual(AppSettings.migrateCounterModeDefaultOnce(ud), .new)
        XCTAssertNil(ud.string(forKey: modeKey))
    }
}
