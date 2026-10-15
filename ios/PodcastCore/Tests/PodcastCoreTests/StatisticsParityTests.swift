import XCTest
@testable import PodcastCore

final class StatisticsParityTests: XCTestCase {
    func testIncludeMarkedPlayed() {
        // Marked played, never listened.
        XCTAssertEqual(StatisticsParity.seconds(recordedWall: nil, isPlayed: true, durationSeconds: 3600, positionSeconds: 0, includeMarkedPlayed: false), 0)
        XCTAssertEqual(StatisticsParity.seconds(recordedWall: nil, isPlayed: true, durationSeconds: 3600, positionSeconds: 0, includeMarkedPlayed: true), 3600)
        // Recorded listening wins when not including.
        XCTAssertEqual(StatisticsParity.seconds(recordedWall: 900, isPlayed: true, durationSeconds: 3600, positionSeconds: 0, includeMarkedPlayed: false), 900)
        // Unfinished without a recording: position.
        XCTAssertEqual(StatisticsParity.seconds(recordedWall: nil, isPlayed: false, durationSeconds: 3600, positionSeconds: 120, includeMarkedPlayed: false), 120)
    }

    func testYearTotals() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let y2025: Int64 = 1_735_689_600_000 + 86_400_000   // 2025-01-02
        let y2026: Int64 = 1_767_225_600_000 + 86_400_000   // 2026-01-02
        let r = StatisticsParity.yearTotals([(y2025, 100), (y2026, 50), (y2026, 25), (y2026, 0)], calendar: cal)
        XCTAssertEqual(r, [.init(year: 2026, seconds: 75, episodes: 2), .init(year: 2025, seconds: 100, episodes: 1)])
    }

    func testDownloadTotals() {
        let r = StatisticsParity.downloadTotals([("a", "A", 10), ("b", "B", 30), ("a", "A", 25)])
        XCTAssertEqual(r.map(\.key), ["a", "b"])
        XCTAssertEqual(r[0].episodes, 2); XCTAssertEqual(r[0].bytes, 35)
    }
}
