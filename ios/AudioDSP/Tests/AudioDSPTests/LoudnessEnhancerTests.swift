import XCTest
@testable import AudioDSP

final class LoudnessEnhancerTests: XCTestCase {
    let profile = LoudnessProfile(targetDB: -18, maxGainDB: 12)

    func testQuietSpeechIsRaisedTowardTargetWithinMax() {
        var c = LoudnessGainComputer(profile: profile)
        for _ in 0..<200 { c.step(levelDB: -26, duration: 0.05) }
        XCTAssertEqual(c.gainDB, 8, accuracy: 0.1)
        var d = LoudnessGainComputer(profile: profile)
        for _ in 0..<200 { d.step(levelDB: -50 + 1, duration: 0.05) }
        XCTAssertEqual(d.gainDB, 12, accuracy: 0.1, "capped at max gain")
    }

    func testLoudSpeechIsNotBoosted() {
        var c = LoudnessGainComputer(profile: profile)
        for _ in 0..<50 { c.step(levelDB: -10, duration: 0.05) }
        XCTAssertEqual(c.gainDB, 0, accuracy: 1e-9)
    }

    func testPausesHoldGainInsteadOfPumpingNoise() {
        var c = LoudnessGainComputer(profile: profile)
        for _ in 0..<200 { c.step(levelDB: -26, duration: 0.05) }
        let held = c.gainDB
        for _ in 0..<50 { c.step(levelDB: -80, duration: 0.05) }
        XCTAssertEqual(c.gainDB, held, accuracy: 1e-9)
    }

    func testAttackIsFasterThanRelease() {
        var up = LoudnessGainComputer(profile: profile)
        up.step(levelDB: -30, duration: 0.05)
        let rise = up.gainDB
        var down = LoudnessGainComputer(profile: profile)
        for _ in 0..<300 { down.step(levelDB: -30, duration: 0.05) }
        let start = down.gainDB
        down.step(levelDB: -5, duration: 0.05)
        XCTAssertGreaterThan(start - down.gainDB, rise * 5)
    }

    func testStageBoostsQuietPCMAndNeverClips() {
        let stage = LoudnessEnhancerStage()
        stage.configure(VolumeAdaptationMode.heavyBoost.loudnessProfile)
        var peak: Float = 0
        for _ in 0..<60 {
            let b = TestBuffer.sine(amplitude: 0.05, frames: 2205)
            b.withBlock { stage.process(&$0) }
            peak = max(peak, b.storage.flatMap { $0 }.map(abs).max()!)
        }
        XCTAssertGreaterThan(stage.currentGainDB, 6)
        XCTAssertGreaterThan(peak, 0.1)
        XCTAssertLessThanOrEqual(peak, 1)
        stage.configure(nil)
        for _ in 0..<60 { TestBuffer.sine(amplitude: 0.05, frames: 2205).withBlock { stage.process(&$0) } }
        XCTAssertEqual(stage.currentGainDB, 0, accuracy: 0.05)
    }

    func testModesMapToProfilesAndStaticGain() {
        XCTAssertNil(VolumeAdaptationMode.lightReduction.loudnessProfile)
        XCTAssertEqual(VolumeAdaptationMode.lightReduction.staticGainFactor, 0.5)
        XCTAssertEqual(VolumeAdaptationMode.heavyBoost.staticGainFactor, 1)
        XCTAssertEqual(VolumeAdaptationMode.mediumBoost.loudnessProfile?.maxGainDB, 12)
    }

    func testGainStageRampsInsteadOfJumping() {
        let stage = GainStage(gain: 1)
        stage.gain = 0
        let b = TestBuffer(channels: 1, frames: 100) { _ in 1 }
        b.withBlock { stage.process(&$0) }
        XCTAssertGreaterThan(b.storage[0][0], 0.9, "first sample still near old gain")
        XCTAssertEqual(b.storage[0][99], 0, accuracy: 1e-6)
        let c = TestBuffer(channels: 1, frames: 10) { _ in 1 }
        c.withBlock { stage.process(&$0) }
        XCTAssertEqual(c.storage[0], Array(repeating: 0, count: 10))
    }
}
