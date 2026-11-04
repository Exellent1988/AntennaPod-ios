import XCTest
@testable import PodcastCore

final class SkipKeepPolicyTests: XCTestCase {
    func testAndroidSemantics() {
        XCTAssertTrue(SkipKeepPolicy.defaultKeepSkippedEpisodes, "Android default on")
        XCTAssertFalse(SkipKeepPolicy.skipMarksPlayed(keepSkipped: true, almostEnded: false), "Kept: stays unplayed in the queue")
        XCTAssertTrue(SkipKeepPolicy.skipMarksPlayed(keepSkipped: true, almostEnded: true), "Smart mark still applies")
        XCTAssertTrue(SkipKeepPolicy.skipMarksPlayed(keepSkipped: false, almostEnded: false))
        XCTAssertEqual(SkipKeepPolicy.resolved(feed: nil, global: true), true)
        XCTAssertEqual(SkipKeepPolicy.resolved(feed: false, global: true), false)
        XCTAssertEqual(SkipKeepPolicy.resolved(feed: true, global: false), true)
    }
}
