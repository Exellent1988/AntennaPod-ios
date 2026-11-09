import XCTest
@testable import PodcastCore

final class SkipIntroOutroTests: XCTestCase {
    func testNormalized() {
        XCTAssertNil(SkipIntroOutro.normalized(nil))
        XCTAssertEqual(SkipIntroOutro.normalized(0), 0)
        XCTAssertEqual(SkipIntroOutro.normalized(42), 42)
        XCTAssertEqual(SkipIntroOutro.normalized(3600), 3600)
        XCTAssertNil(SkipIntroOutro.normalized(-1))
        XCTAssertNil(SkipIntroOutro.normalized(3601))
    }

    func testResolvedOverrideBeatsGlobal() {
        XCTAssertEqual(SkipIntroOutro.resolved(feed: nil, global: 30), 30)
        XCTAssertEqual(SkipIntroOutro.resolved(feed: 45, global: 30), 45)
        XCTAssertEqual(SkipIntroOutro.resolved(feed: 0, global: 30), 0, "Override 0 = off for this podcast")
        XCTAssertEqual(SkipIntroOutro.resolved(feed: nil, global: -5), 0)
    }

    func testIntroSeekFits() {
        XCTAssertFalse(SkipIntroOutro.introSeekFits(intro: 0, outro: 0, duration: 600))
        XCTAssertTrue(SkipIntroOutro.introSeekFits(intro: 30, outro: 0, duration: 0), "Unknown duration allows the seek")
        XCTAssertTrue(SkipIntroOutro.introSeekFits(intro: 30, outro: 60, duration: 600))
        XCTAssertFalse(SkipIntroOutro.introSeekFits(intro: 600, outro: 0, duration: 600))
        XCTAssertFalse(SkipIntroOutro.introSeekFits(intro: 560, outro: 60, duration: 600), "Would land inside the ending")
        XCTAssertTrue(SkipIntroOutro.introSeekFits(intro: 30, outro: 600, duration: 600), "Ending ≥ duration is ignored")
    }

    func testShouldSkipEnding() {
        XCTAssertFalse(SkipIntroOutro.shouldSkipEnding(outro: 0, position: 590, duration: 600))
        XCTAssertFalse(SkipIntroOutro.shouldSkipEnding(outro: 30, position: 500, duration: 600))
        XCTAssertTrue(SkipIntroOutro.shouldSkipEnding(outro: 30, position: 570, duration: 600))
        XCTAssertTrue(SkipIntroOutro.shouldSkipEnding(outro: 30, position: 599, duration: 600))
        XCTAssertFalse(SkipIntroOutro.shouldSkipEnding(outro: 30, position: 570, duration: 0), "Unknown duration")
        XCTAssertFalse(SkipIntroOutro.shouldSkipEnding(outro: 600, position: 10, duration: 600), "Ending ≥ duration")
        XCTAssertFalse(SkipIntroOutro.shouldSkipEnding(outro: 30, position: 0.5, duration: 20), "Not at the very start")
    }
}
