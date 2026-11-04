import XCTest
@testable import AntennaPod

/// Android SubscriptionViewHolder.bind / subscription_grid_item.xml / SubscriptionFragment column menu.
@MainActor
final class SubscriptionsGridParityTests: XCTestCase {
    func testTitleSizeAndPaddingFollowColumnCount() {
        XCTAssertEqual(SubscriptionGridCell.titleFontSize(columns: 2), 16)
        XCTAssertEqual(SubscriptionGridCell.titleFontSize(columns: 3), 15)
        XCTAssertEqual(SubscriptionGridCell.titleFontSize(columns: 4), 14)
        XCTAssertEqual(SubscriptionGridCell.titleFontSize(columns: 5), 14)
        XCTAssertGreaterThan(SubscriptionGridCell.titlePadding(columns: 3), SubscriptionGridCell.titlePadding(columns: 4))
    }

    func testNumberOfColumnsMenuMapsListAndGrid() {
        XCTAssertEqual(SubscriptionsDisplayMode.columnChoices, [1, 2, 3, 4, 5])
        XCTAssertEqual(SubscriptionsDisplayMode.columnChoice(mode: .list, gridColumns: 4), 1)
        XCTAssertEqual(SubscriptionsDisplayMode.columnChoice(mode: .grid, gridColumns: 4), 4)
        XCTAssertTrue(SubscriptionsDisplayMode.apply(columnChoice: 1, gridColumns: 4) == (.list, 4), "List keeps the grid count")
        XCTAssertTrue(SubscriptionsDisplayMode.apply(columnChoice: 5, gridColumns: 3) == (.grid, 5))
        XCTAssertEqual(SubscriptionsDisplayMode.columnChoiceLabel(3), "3")
    }

    func testNewInstallsStartInTheGridLikeAndroid() {
        XCTAssertEqual(SubscriptionsDisplayMode.initial(stored: nil, isFreshInstall: true), .grid)
        XCTAssertEqual(SubscriptionsDisplayMode.initial(stored: nil, isFreshInstall: false), .list, "existing users keep the list")
        XCTAssertEqual(SubscriptionsDisplayMode.initial(stored: "list", isFreshInstall: true), .list, "saved choice wins")
        XCTAssertEqual(SubscriptionsDisplayMode.initial(stored: "grid", isFreshInstall: false), .grid)
    }

    func testAddButtonHiddenWhenLockedOrSelecting() {
        XCTAssertTrue(SubscriptionsAddButton.isVisible(addLocked: false, selecting: false))
        XCTAssertFalse(SubscriptionsAddButton.isVisible(addLocked: true, selecting: false), "parental lock")
        XCTAssertFalse(SubscriptionsAddButton.isVisible(addLocked: false, selecting: true), "select mode")
    }

    func testSelectedCardShrinksLikeAndroid() {
        XCTAssertEqual(FeedGridSelectionModifier.cardInset(selecting: true, selected: true), 12)
        XCTAssertEqual(FeedGridSelectionModifier.cardInset(selecting: true, selected: false), 0)
        XCTAssertEqual(FeedGridSelectionModifier.cardInset(selecting: false, selected: true), 0)
    }

    func testTabletDefaultsLikeAndroidSw600dp() {
        XCTAssertEqual(SubscriptionsDisplayMode.defaultGridColumns(isPad: true), 5)
        XCTAssertEqual(SubscriptionsDisplayMode.defaultGridColumns(isPad: false), 3)
        XCTAssertEqual(SubscriptionsDisplayMode.listColumns(isRegularWidth: true), 2)
        XCTAssertEqual(SubscriptionsDisplayMode.listColumns(isRegularWidth: false), 1)
    }
}
