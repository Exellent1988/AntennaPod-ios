import XCTest
@testable import PodcastCore

final class ListeningTimeTests: XCTestCase {
    func testTwoXHalvesWallTime() {
        var a = ListeningSessionAccumulator()
        for _ in 0..<10 { a.tick(wallDelta: 0.5, mediaDelta: 1.0, isPlaying: true) }
        XCTAssertEqual(a.wallSeconds, 5, accuracy: 1e-9)
        XCTAssertEqual(a.mediaSeconds, 10, accuracy: 1e-9)
    }

    func testPausedAndSuspendedTicksIgnored() {
        var a = ListeningSessionAccumulator()
        a.tick(wallDelta: 0.5, mediaDelta: 0.5, isPlaying: false)
        a.tick(wallDelta: 60, mediaDelta: 60, isPlaying: true)
        XCTAssertEqual(a.wallSeconds, 0)
    }

    func testSeekCountsNoMediaTime() {
        var a = ListeningSessionAccumulator()
        a.tick(wallDelta: 0.5, mediaDelta: 300, isPlaying: true)
        a.tick(wallDelta: 0.5, mediaDelta: -30, isPlaying: true)
        XCTAssertEqual(a.wallSeconds, 1, accuracy: 1e-9)
        XCTAssertEqual(a.mediaSeconds, 0)
    }

    func testDrainClears() {
        var a = ListeningSessionAccumulator()
        a.tick(wallDelta: 1, mediaDelta: 1.5, isPlaying: true)
        let d = a.drain()
        XCTAssertEqual(d.wall, 1); XCTAssertEqual(d.media, 1.5)
        XCTAssertEqual(a.wallSeconds, 0)
    }

    func testRulePrefersRecordedWall() {
        XCTAssertEqual(ListeningTimeRule.seconds(recordedWall: 1800, isPlayed: true, durationSeconds: 3600, positionSeconds: 0), 1800)
        XCTAssertEqual(ListeningTimeRule.seconds(recordedWall: nil, isPlayed: true, durationSeconds: 3600, positionSeconds: 0), 3600)
        XCTAssertEqual(ListeningTimeRule.seconds(recordedWall: 0, isPlayed: false, durationSeconds: 0, positionSeconds: 90), 90)
        XCTAssertEqual(ListeningTimeRule.seconds(recordedWall: nil, isPlayed: false, durationSeconds: 0, positionSeconds: 0.5), 0)
    }

    func testTimeSaved() {
        XCTAssertEqual(ListeningTimeRule.timeSaved(recordedWall: 1800, recordedMedia: 3600), 1800)
        XCTAssertEqual(ListeningTimeRule.timeSaved(recordedWall: 100, recordedMedia: 80), 0)
    }
}
