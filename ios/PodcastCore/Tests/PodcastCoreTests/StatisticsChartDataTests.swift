import XCTest
@testable import PodcastCore

final class StatisticsChartDataTests: XCTestCase {
    func testPieCapsAndMergesOther() {
        let items = (1...8).map { (label: "P\($0)", seconds: Double($0)) } + [(label: "Z", seconds: 0)]
        let s = StatisticsChartData.pieSlices(items, maxSlices: 4, otherLabel: "Other")
        XCTAssertEqual(s.map(\.label), ["P8", "P7", "P6", "Other"])
        XCTAssertEqual(s.last?.seconds, 15); XCTAssertEqual(s.last?.isOther, true)
        XCTAssertEqual(StatisticsChartData.pieSlices([("A", 1), ("B", 0)], otherLabel: "O").map(\.label), ["A"])
    }

    func testMonthTotals() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let jan2026: Int64 = 1_767_225_600_000 + 86_400_000
        let mar2026: Int64 = jan2026 + 60 * 86_400_000
        let m = StatisticsChartData.monthTotals([(jan2026, 10), (mar2026, 5), (mar2026, 5), (jan2026 - 3 * 86_400_000, 99)], year: 2026, calendar: cal)
        XCTAssertEqual(m[0], 10); XCTAssertEqual(m[2], 10); XCTAssertEqual(m.reduce(0, +), 20)
    }
}
