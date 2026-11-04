import XCTest
@testable import AudioDSP

final class AudioProcessingChainTests: XCTestCase {
    func testRmsOfSilenceIsFloor() {
        let b = TestBuffer(channels: 2, frames: 512) { _ in 0 }
        XCTAssertEqual(b.withBlock { AudioLevel.rmsDB($0) }, AudioLevel.floorDB)
    }

    func testRmsOfFullScaleSineIsAboutMinus3dB() {
        let db = TestBuffer.sine(amplitude: 1).withBlock { AudioLevel.rmsDB($0) }
        XCTAssertEqual(db, -3.01, accuracy: 0.1)
    }

    func testUnityGainLeavesSamplesUntouched() {
        let b = TestBuffer.sine(amplitude: 0.5)
        let before = b.storage
        b.withBlock { GainStage(gain: 1).process(&$0) }
        XCTAssertEqual(b.storage, before)
    }

    func testReductionScalesLinearly() {
        let b = TestBuffer(channels: 1, frames: 4) { _ in 0.5 }
        b.withBlock { GainStage(gain: 0.5).process(&$0) }
        XCTAssertEqual(b.storage[0], [0.25, 0.25, 0.25, 0.25])
    }

    func testBoostNeverExceedsFullScale() {
        let b = TestBuffer.sine(amplitude: 0.9)
        b.withBlock { GainStage(gain: 8).process(&$0) }
        XCTAssertLessThanOrEqual(b.storage.flatMap { $0 }.map(abs).max()!, 1.0)
    }

    func testChainRunsStagesInOrder() {
        let chain = AudioProcessingChain(stages: [GainStage(gain: 0.5), GainStage(gain: 0.5)])
        let b = TestBuffer(channels: 1, frames: 1) { _ in 1 }
        b.withBlock { chain.process(&$0) }
        XCTAssertEqual(b.storage[0][0], 0.25, accuracy: 1e-6)
        XCTAssertEqual(chain.stageCount, 2)
    }
}
