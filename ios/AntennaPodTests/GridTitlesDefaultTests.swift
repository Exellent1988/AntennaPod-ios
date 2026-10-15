import XCTest
@testable import AntennaPod

/// Android pref_show_subscription_title: off for new installs (UserPreferences.shouldShowSubscriptionTitle
/// default false), on for existing iOS users; a saved choice always wins.
final class GridTitlesDefaultTests: XCTestCase {
    func testNewInstallStartsWithTitlesOff() {
        XCTAssertFalse(AppSettings.initialGridShowTitles(stored: nil, isFreshInstall: true))
    }

    func testExistingUserKeepsTitlesOn() {
        XCTAssertTrue(AppSettings.initialGridShowTitles(stored: nil, isFreshInstall: false))
    }

    func testSavedChoiceWins() {
        XCTAssertTrue(AppSettings.initialGridShowTitles(stored: true, isFreshInstall: true))
        XCTAssertFalse(AppSettings.initialGridShowTitles(stored: false, isFreshInstall: false))
    }

}
