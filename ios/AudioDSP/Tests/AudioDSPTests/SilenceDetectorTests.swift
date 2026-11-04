import XCTest
@testable import AudioDSP

final class SilenceDetectorTests: XCTestCase {
    func testShortPauseIsNotSkipped() {
        var d = SilenceDetector(minimumSilence: 0.3)
        XCTAssertFalse(d.feed(levelDB: -80, duration: 0.1))
        XCTAssertFalse(d.feed(levelDB: -80, duration: 0.1))
        XCTAssertFalse(d.isSkipping)
        d.feed(levelDB: -20, duration: 0.1)
        d.feed(levelDB: -80, duration: 0.2)
        XCTAssertFalse(d.isSkipping, "speech resets the silence counter")
    }

    func testLongSilenceStartsSkippingAndSpeechStopsIt() {
        var d = SilenceDetector(minimumSilence: 0.3)
        d.feed(levelDB: -80, duration: 0.2)
        XCTAssertTrue(d.feed(levelDB: -80, duration: 0.2))
        XCTAssertTrue(d.isSkipping)
        XCTAssertTrue(d.feed(levelDB: -15, duration: 0.02))
        XCTAssertFalse(d.isSkipping)
    }

    func testHysteresisKeepsSkippingThroughQuietNoise() {
        var d = SilenceDetector(thresholdDB: -45, releaseDB: -40, minimumSilence: 0.1)
        d.feed(levelDB: -60, duration: 0.2)
        XCTAssertTrue(d.isSkipping)
        d.feed(levelDB: -42, duration: 0.1) // above threshold, below release
        XCTAssertTrue(d.isSkipping)
    }

    func testEffectiveRate() {
        XCTAssertEqual(SkipSilenceRate.effectiveRate(base: 1, isSkipping: false, maxRate: 2), 1)
        XCTAssertEqual(SkipSilenceRate.effectiveRate(base: 1, isSkipping: true, maxRate: 2), 2)
        XCTAssertEqual(SkipSilenceRate.effectiveRate(base: 1, isSkipping: true, maxRate: 4), 3)
        XCTAssertEqual(SkipSilenceRate.effectiveRate(base: 2.5, isSkipping: true, maxRate: 2), 2.5)
    }

    func testTimeSaved() {
        XCTAssertEqual(SkipSilenceRate.timeSaved(mediaSeconds: 3, base: 1, fastRate: 3), 2, accuracy: 1e-9)
        XCTAssertEqual(SkipSilenceRate.timeSaved(mediaSeconds: 3, base: 1, fastRate: 1), 0)
    }

    func testFeedOverride() {
        XCTAssertTrue(SkipSilenceRate.isEnabled(feedOverride: nil, global: true))
        XCTAssertFalse(SkipSilenceRate.isEnabled(feedOverride: false, global: true))
        XCTAssertTrue(SkipSilenceRate.isEnabled(feedOverride: true, global: false))
    }

    func testStageReportsTransitionsOnRealPCM() {
        let stage = SilenceAnalysisStage(detector: SilenceDetector(minimumSilence: 0.3))
        var events: [Bool] = []
        stage.onChange = { events.append($0) }
        stage.isEnabled = true
        let silence = TestBuffer(channels: 2, frames: 4410) { _ in 0.0001 } // 0.1 s at -80 dBFS
        for _ in 0..<4 { silence.withBlock { stage.process(&$0) } }
        TestBuffer.sine(amplitude: 0.3).withBlock { stage.process(&$0) }
        XCTAssertEqual(events, [true, false])
        XCTAssertGreaterThan(stage.skippedMediaSeconds, 0)
    }

    func testDisabledStageDoesNothing() {
        let stage = SilenceAnalysisStage()
        var fired = false
        stage.onChange = { _ in fired = true }
        let silence = TestBuffer(channels: 1, frames: 44_100) { _ in 0 }
        silence.withBlock { stage.process(&$0) }
        XCTAssertFalse(fired)
    }
}
