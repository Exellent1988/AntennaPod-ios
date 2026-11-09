import XCTest
@testable import AntennaPod

final class BackgroundRefreshTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testManualNeverSchedules() {
        XCTAssertNil(FeedRefreshCoordinator.nextBeginDate(interval: .manual, lastRefresh: nil, now: now))
    }

    func testNeverRefreshedSchedulesNow() {
        XCTAssertEqual(FeedRefreshCoordinator.nextBeginDate(interval: .oneHour, lastRefresh: nil, now: now), now)
    }

    func testSchedulesAfterIntervalFromLastRefresh() {
        let last = now.addingTimeInterval(-600)
        XCTAssertEqual(
            FeedRefreshCoordinator.nextBeginDate(interval: .oneHour, lastRefresh: last, now: now),
            last.addingTimeInterval(3600)
        )
    }

    func testOverdueClampsToNow() {
        let last = now.addingTimeInterval(-90_000)
        XCTAssertEqual(FeedRefreshCoordinator.nextBeginDate(interval: .twentyFourHours, lastRefresh: last, now: now), now)
    }
}
