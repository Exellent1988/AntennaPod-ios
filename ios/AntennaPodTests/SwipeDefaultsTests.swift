import XCTest
@testable import AntennaPod

/// Android ui/swipeactions/SwipeActions.java getPrefsWithDefaults: per-screen pairs for new installs only.
@MainActor
final class SwipeDefaultsTests: XCTestCase {
    func testFreshInstallGetsAndroidPairs() {
        let d = AppSettings.initialSwipeActions(stored: nil, isFreshInstall: true)
        XCTAssertEqual(d["inbox.leading"], EpisodeSwipeAction.toggleQueue.rawValue)
        XCTAssertEqual(d["inbox.trailing"], EpisodeSwipeAction.archive.rawValue)
        XCTAssertEqual(d["queue.leading"], EpisodeSwipeAction.toggleQueue.rawValue)
        XCTAssertEqual(d["downloads.trailing"], EpisodeSwipeAction.deleteDownload.rawValue)
        XCTAssertEqual(d["history.leading"], EpisodeSwipeAction.removeFromHistory.rawValue)
        XCTAssertEqual(d["favorites.trailing"], EpisodeSwipeAction.toggleFavorite.rawValue)
        XCTAssertEqual(d["episodes.leading"], EpisodeSwipeAction.toggleFavorite.rawValue)
        XCTAssertEqual(d["feed.trailing"], EpisodeSwipeAction.download.rawValue)
        XCTAssertEqual(d.count, SwipeList.allCases.count * 2)
    }

    func testExistingUserWithoutSavedSwipesKeepsListDefaults() {
        XCTAssertEqual(AppSettings.initialSwipeActions(stored: nil, isFreshInstall: false), [:])
    }

    func testEmptyMigrationDictionaryOnFreshInstallStillGetsAndroidPairs() {
        XCTAssertEqual(AppSettings.initialSwipeActions(stored: [:], isFreshInstall: true), AppSettings.androidDefaultSwipeActions)
        XCTAssertEqual(AppSettings.initialSwipeActions(stored: [:], isFreshInstall: false), [:])
    }

    func testSavedSwipesAreNeverReplaced() {
        let saved = ["inbox.leading": EpisodeSwipeAction.togglePlayed.rawValue]
        XCTAssertEqual(AppSettings.initialSwipeActions(stored: saved, isFreshInstall: true), saved)
    }

    func testEveryAndroidDefaultIsOfferedOnItsList() {
        for list in SwipeList.allCases {
            let pair = EpisodeSwipeAction.androidDefault(for: list)
            let offered = EpisodeSwipeAction.available(for: list)
            XCTAssertTrue(offered.contains(pair.leading), "\(list) leading")
            XCTAssertTrue(offered.contains(pair.trailing), "\(list) trailing")
        }
    }

    /// SwipeActionsDialog adds ShareSwipeAction on every screen.
    func testShareOfferedOnEveryList() {
        for list in SwipeList.allCases {
            XCTAssertTrue(EpisodeSwipeAction.available(for: list).contains(.share), "\(list)")
        }
    }
}
