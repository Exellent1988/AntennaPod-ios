import XCTest
@testable import PodcastCore

final class SpeedPresetsTests: XCTestCase {
    func testAndroidDefaultAndJSONFormat() {
        XCTAssertEqual(SpeedPresets.androidDefault, [1.0, 1.25, 1.5])
        XCTAssertEqual(SpeedPresets.encode(SpeedPresets.androidDefault), #"["1.00","1.25","1.50"]"#)
        XCTAssertEqual(SpeedPresets.decode(#"["1.00","1.25","1.50"]"#), [1.0, 1.25, 1.5])
        XCTAssertEqual(SpeedPresets.decode("[2, 0.8, 0.8]"), [0.8, 2.0], "numbers, dedupe, sorted")
        XCTAssertNil(SpeedPresets.decode("[]"))
        XCTAssertNil(SpeedPresets.decode("garbage"))
        XCTAssertEqual(SpeedPresets.decode(#"["9.00","1.10"]"#), [1.1], "out of range dropped")
    }

    func testAddKeepsSortedAndRejectsDuplicate() {
        var r = SpeedPresets.adding(1.1, to: [1.0, 1.25, 1.5])
        XCTAssertTrue(r.added); XCTAssertEqual(r.list, [1.0, 1.1, 1.25, 1.5])
        r = SpeedPresets.adding(1.25, to: r.list)
        XCTAssertFalse(r.added, "preset already exists")
        r = SpeedPresets.adding(1.333, to: [1.0])
        XCTAssertEqual(r.list, [1.0, 1.35], "0.05 grid")
        XCTAssertFalse(SpeedPresets.adding(5, to: [1.0]).added)
    }

    func testRemoveKeepsAtLeastOne() {
        XCTAssertEqual(SpeedPresets.removing(1.25, from: [1.0, 1.25]).list, [1.0])
        XCTAssertFalse(SpeedPresets.removing(1.0, from: [1.0]).removed)
        XCTAssertFalse(SpeedPresets.removing(2.0, from: [1.0, 1.5]).removed)
    }

    func testNextCyclesAndWraps() {
        let l: [Float] = [1.0, 1.25, 1.5]
        XCTAssertEqual(SpeedPresets.next(after: 1.0, in: l), 1.25)
        XCTAssertEqual(SpeedPresets.next(after: 1.5, in: l), 1.0)
        XCTAssertEqual(SpeedPresets.next(after: 1.1, in: l), 1.25, "between presets → next higher")
        XCTAssertEqual(SpeedPresets.next(after: 2.5, in: l), 1.0)
        XCTAssertNil(SpeedPresets.next(after: 1, in: []))
    }

    func testLoadDefaultsFreshVsExistingInstall() {
        let d = UserDefaults(suiteName: "SpeedPresetsTests-\(UUID().uuidString)")!
        XCTAssertEqual(SpeedPresets.load(from: d, hasExistingData: false), SpeedPresets.androidDefault)
        XCTAssertEqual(SpeedPresets.load(from: d, hasExistingData: true), SpeedPresets.legacyIOSDefault)
        SpeedPresets.save([2.0, 0.75], to: d)
        XCTAssertEqual(d.string(forKey: SpeedPresets.defaultsKey), #"["0.75","2.00"]"#)
        XCTAssertEqual(SpeedPresets.load(from: d, hasExistingData: true), [0.75, 2.0])
    }
}
