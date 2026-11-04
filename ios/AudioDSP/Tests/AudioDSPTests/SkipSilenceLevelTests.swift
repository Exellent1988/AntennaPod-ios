import XCTest
@testable import AudioDSP

final class SkipSilenceLevelTests: XCTestCase {
    func testLevelsGetMoreAggressive() {
        let l: [SkipSilenceLevel] = [.mild, .medium, .aggressive]
        XCTAssertEqual(l.map(\.speedup), [2, 3, 4])
        XCTAssertTrue(l[0].minimumSilence > l[1].minimumSilence && l[1].minimumSilence > l[2].minimumSilence)
        XCTAssertTrue(l[0].thresholdDB < l[2].thresholdDB)
        XCTAssertEqual(SkipSilenceLevel.medium.detector.releaseDB, -40)
    }

    func testResolution() {
        XCTAssertEqual(SkipSilenceLevel.resolved(feedLevel: nil, feedEnabled: nil, globalEnabled: false, globalLevel: .aggressive), .off)
        XCTAssertEqual(SkipSilenceLevel.resolved(feedLevel: nil, feedEnabled: nil, globalEnabled: true, globalLevel: .mild), .mild)
        XCTAssertEqual(SkipSilenceLevel.resolved(feedLevel: nil, feedEnabled: true, globalEnabled: false, globalLevel: .aggressive), .aggressive)
        XCTAssertEqual(SkipSilenceLevel.resolved(feedLevel: nil, feedEnabled: false, globalEnabled: true, globalLevel: .mild), .off)
        XCTAssertEqual(SkipSilenceLevel.resolved(feedLevel: .mild, feedEnabled: false, globalEnabled: true, globalLevel: .aggressive), .mild)
        XCTAssertEqual(SkipSilenceLevel.resolved(feedLevel: nil, feedEnabled: nil, globalEnabled: true, globalLevel: .off), .medium)
    }

    func testRampStepsAreBoundedAndEndAtTarget() {
        let s = RateRamp.steps(from: 1, to: 3, maxStep: 0.5)
        XCTAssertEqual(s, [1.5, 2, 2.5, 3])
        XCTAssertEqual(RateRamp.steps(from: 3, to: 1.2, maxStep: 1).last, 1.2)
        XCTAssertEqual(RateRamp.steps(from: 1, to: 1, maxStep: 0.5), [1])
    }

    func testMildIgnoresPauseThatAggressiveSkips() {
        var mild = SkipSilenceLevel.mild.detector
        var aggressive = SkipSilenceLevel.aggressive.detector
        for _ in 0..<4 { mild.feed(levelDB: -70, duration: 0.1); aggressive.feed(levelDB: -70, duration: 0.1) }
        XCTAssertFalse(mild.isSkipping)
        XCTAssertTrue(aggressive.isSkipping)
    }

    func testConfigureEndsActiveSkip() {
        let stage = SilenceAnalysisStage(detector: SkipSilenceLevel.aggressive.detector)
        var events: [Bool] = []
        stage.onChange = { events.append($0) }
        stage.isEnabled = true
        let silence = TestBuffer(channels: 1, frames: 44_100) { _ in 0 }
        silence.withBlock { stage.process(&$0) }
        stage.configure(SkipSilenceLevel.mild.detector)
        XCTAssertEqual(events, [true, false])
    }
}
