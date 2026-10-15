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
}
