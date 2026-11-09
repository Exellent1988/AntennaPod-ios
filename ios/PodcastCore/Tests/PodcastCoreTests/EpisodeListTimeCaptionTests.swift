import XCTest
@testable import PodcastCore

final class EpisodeListTimeCaptionTests: XCTestCase {
    private func v(_ d: Double?, _ p: Double, played: Bool = false, remaining: Bool = true,
                   speedOn: Bool = false, speed: Float? = nil) -> EpisodeListTimeCaption.Value? {
        EpisodeListTimeCaption.value(durationSeconds: d, positionSeconds: p, isPlayed: played,
                                     showRemaining: remaining, respectsSpeed: speedOn, speed: speed)
    }

    func testInProgressShowsRemainingOnlyWhenEnabled() {
        XCTAssertEqual(v(3600, 600), .init(seconds: 3000, isRemaining: true))
        XCTAssertEqual(v(3600, 600, remaining: false), .init(seconds: 3600, isRemaining: false))
    }

    func testNotStartedOrPlayedShowsDuration() {
        XCTAssertEqual(v(3600, 0), .init(seconds: 3600, isRemaining: false))
        XCTAssertEqual(v(3600, 0.5), .init(seconds: 3600, isRemaining: false), "sub-second noise")
        XCTAssertEqual(v(3600, 600, played: true), .init(seconds: 3600, isRemaining: false))
        XCTAssertEqual(v(3600, 3600), .init(seconds: 3600, isRemaining: false))
        XCTAssertNil(v(nil, 10)); XCTAssertNil(v(0, 10))
    }

    func testRespectsSpeedDividesAllTimes() {
        XCTAssertEqual(v(3600, 600, speedOn: true, speed: 1.5), .init(seconds: 2000, isRemaining: true))
        XCTAssertEqual(v(3600, 0, speedOn: true, speed: 2), .init(seconds: 1800, isRemaining: false))
        XCTAssertEqual(v(3600, 600, speedOn: false, speed: 2), .init(seconds: 3000, isRemaining: true))
        XCTAssertEqual(v(3600, 0, speedOn: true, speed: 0.25)?.seconds, 7200, "speed clamped to 0.5")
    }

    func testFormat() {
        XCTAssertEqual(EpisodeListTimeCaption.format(.init(seconds: 3000, isRemaining: true)), "\u{2212}50:00")
        XCTAssertEqual(EpisodeListTimeCaption.format(.init(seconds: 3725.9, isRemaining: false)), "1:02:05")
    }
}
