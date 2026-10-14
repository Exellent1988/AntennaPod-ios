import SwiftUI
import XCTest
@testable import AntennaPod

/// NAV-10 / NAV-17 view preferences live in AppSettings and survive a JSON backup round-trip.
@MainActor
final class ViewPrefsBackupTests: XCTestCase {
    func testBackupRoundTripKeepsSubscriptionsDisplayAndSwipeActions() throws {
        let settings = AppSettings()
        let original = settings.backupSnapshot()
        defer { settings.applyBackupSnapshot(original) }
        settings.subscriptionsDisplayMode = .grid
        settings.subscriptionsGridColumns = 4
        settings.subscriptionsCounterMode = .downloaded
        settings.swipeActions = [:]
        settings.setSwipeAction(.toggleFavorite, .inbox, .leading)
        settings.setSwipeAction(.none, .queue, .trailing)

        let data = try JSONEncoder().encode(settings.backupSnapshot())
        let snap = try JSONDecoder().decode(AppSettingsBackupSnapshot.self, from: data)

        settings.subscriptionsDisplayMode = .list
        settings.subscriptionsGridColumns = 2
        settings.subscriptionsCounterMode = .none
        settings.swipeActions = [:]

        settings.applyBackupSnapshot(snap)
        XCTAssertEqual(settings.subscriptionsDisplayMode, .grid)
        XCTAssertEqual(settings.subscriptionsGridColumns, 4)
        XCTAssertEqual(settings.subscriptionsCounterMode, .downloaded)
        XCTAssertEqual(settings.swipeAction(.inbox, .leading), .toggleFavorite)
        XCTAssertEqual(settings.swipeAction(.queue, .trailing), EpisodeSwipeAction.none)
        XCTAssertEqual(settings.swipeAction(.history, .leading), .standard)

        // A fresh instance reads the same values back from UserDefaults.
        let reloaded = AppSettings()
        XCTAssertEqual(reloaded.subscriptionsGridColumns, 4)
        XCTAssertEqual(reloaded.swipeAction(.inbox, .leading), .toggleFavorite)
    }

    func testOlderBackupWithoutViewPrefsKeepsCurrentValues() throws {
        let settings = AppSettings()
        let original = settings.backupSnapshot()
        defer { settings.applyBackupSnapshot(original) }
        settings.subscriptionsDisplayMode = .grid
        var snap = settings.backupSnapshot()
        snap.subscriptionsDisplayMode = nil
        snap.swipeActions = nil
        settings.applyBackupSnapshot(snap)
        XCTAssertEqual(settings.subscriptionsDisplayMode, .grid)
    }

    func testMigratesAppStorageValuesOnce() {
        let suite = "ViewPrefsBackupTests.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suite)!
        defer { ud.removePersistentDomain(forName: suite) }
        ud.set("grid", forKey: "subscriptions.displayMode")
        ud.set(5, forKey: "subscriptions.gridColumns")
        ud.set("archive", forKey: "swipe.inbox.trailing")
        ud.set("standard", forKey: "swipe.queue.leading")

        AppSettings.migrateViewPrefsFromAppStorageOnce(ud)

        XCTAssertEqual(ud.string(forKey: "settings.subscriptionsDisplayMode"), "grid")
        XCTAssertEqual(ud.integer(forKey: "settings.subscriptionsGridColumns"), 5)
        XCTAssertEqual(ud.dictionary(forKey: "settings.swipeActions") as? [String: String], ["inbox.trailing": "archive"])
        XCTAssertNil(ud.object(forKey: "subscriptions.displayMode"))
        XCTAssertNil(ud.object(forKey: "swipe.inbox.trailing"))

        // Second run is a no-op even if an old key reappears.
        ud.set("list", forKey: "subscriptions.displayMode")
        AppSettings.migrateViewPrefsFromAppStorageOnce(ud)
        XCTAssertEqual(ud.string(forKey: "settings.subscriptionsDisplayMode"), "grid")
    }
}
