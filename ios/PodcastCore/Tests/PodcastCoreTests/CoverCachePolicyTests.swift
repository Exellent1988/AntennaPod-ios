import XCTest
@testable import PodcastCore

final class CoverCachePolicyTests: XCTestCase {
    func testOptions() {
        XCTAssertEqual(CoverCachePolicy.sizeOptionsMB, [20, 50, 100, 250, 500])
        XCTAssertEqual(CoverCachePolicy.normalizedSizeMB(nil), 100)
        XCTAssertEqual(CoverCachePolicy.normalizedSizeMB(33), 100)
        XCTAssertEqual(CoverCachePolicy.normalizedSizeMB(250), 250)
    }

    func testLRUEviction() {
        let t = Date(timeIntervalSince1970: 1000)
        let e = [CoverCachePolicy.Entry(name: "new", bytes: 40, lastAccess: t.addingTimeInterval(30)),
                 CoverCachePolicy.Entry(name: "old", bytes: 40, lastAccess: t),
                 CoverCachePolicy.Entry(name: "mid", bytes: 40, lastAccess: t.addingTimeInterval(10))]
        XCTAssertEqual(CoverCachePolicy.evictions(e, limitBytes: 200), [])
        XCTAssertEqual(CoverCachePolicy.evictions(e, limitBytes: 100), ["old"])
        XCTAssertEqual(CoverCachePolicy.evictions(e, limitBytes: 40), ["old", "mid"])
        XCTAssertEqual(CoverCachePolicy.evictions(e, limitBytes: 0), ["old", "mid", "new"])
    }
}
