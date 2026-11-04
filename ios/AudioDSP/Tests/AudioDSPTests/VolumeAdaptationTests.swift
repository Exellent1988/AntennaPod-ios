import XCTest
@testable import AudioDSP

final class VolumeAdaptationTests: XCTestCase {
    func testAndroidReductionFactors() {
        XCTAssertEqual(VolumeAdaptationMode.off.gainFactor, 1)
        XCTAssertEqual(VolumeAdaptationMode.lightReduction.gainFactor, 0.5)
        XCTAssertEqual(VolumeAdaptationMode.heavyReduction.gainFactor, 0.2)
    }

    func testBoostsIncrease() {
        let b = [VolumeAdaptationMode.lightBoost, .mediumBoost, .heavyBoost].map(\.gainFactor)
        XCTAssertEqual(b[0], 1.995, accuracy: 0.01)
        XCTAssertTrue(b[0] < b[1] && b[1] < b[2])
    }

    func testFeedOverrideWins() {
        XCTAssertEqual(VolumeAdaptationMode.resolved(feed: nil, global: .lightBoost), .lightBoost)
        XCTAssertEqual(VolumeAdaptationMode.resolved(feed: .off, global: .lightBoost), .off)
    }

    func testPipelineGainCombinesBoostAndMode() {
        XCTAssertEqual(VolumeAdaptationMode.pipelineGain(boostPercent: 200, mode: .lightReduction), 1, accuracy: 1e-6)
        XCTAssertEqual(VolumeAdaptationMode.pipelineGain(boostPercent: 100, mode: .off), 1)
    }

    func testRawValuesStableForPersistence() throws {
        let data = try JSONEncoder().encode([VolumeAdaptationMode.heavyBoost])
        XCTAssertEqual(String(data: data, encoding: .utf8), "[\"heavyBoost\"]")
    }
}
