import XCTest
@testable import AntennaPod

final class CarPlayBrowseModelTests: XCTestCase {
    func testDurationText() {
        XCTAssertNil(CarPlayBrowseModel.durationText(0))
        XCTAssertNil(CarPlayBrowseModel.durationText(.nan))
        XCTAssertEqual(CarPlayBrowseModel.durationText(65), "1:05")
        XCTAssertEqual(CarPlayBrowseModel.durationText(3725), "1:02:05")
    }

    func testNewerFirstPutsUndatedLast() {
        let dates: [Int64?] = [nil, 10, 30, 20]
        XCTAssertEqual(dates.sorted(by: CarPlayBrowseModel.newerFirst), [30, 20, 10, nil])
    }

    func testEmptyInputsGiveEmptyRows() {
        XCTAssertTrue(CarPlayBrowseModel.subscriptionRows([]).isEmpty)
        XCTAssertTrue(CarPlayBrowseModel.queueRows([]) { _ in nil }.isEmpty)
        XCTAssertTrue(CarPlayBrowseModel.downloadRows(feeds: []) { _ in true }.isEmpty)
    }
}
