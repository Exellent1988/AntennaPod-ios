import XCTest
@testable import PodcastCore

final class InterruptionPolicyTests: XCTestCase {
    func testSessionModeMatchesPauseOrDuck() {
        XCTAssertTrue(InterruptionPolicy.defaultPauseForInterruptions, "Android default on")
        XCTAssertEqual(InterruptionPolicy.sessionMode(pauseForInterruptions: true, volumeAdaptationOn: false, videoSurface: false), .spokenAudio)
        XCTAssertEqual(InterruptionPolicy.sessionMode(pauseForInterruptions: true, volumeAdaptationOn: true, videoSurface: true), .spokenAudio)
        XCTAssertEqual(InterruptionPolicy.sessionMode(pauseForInterruptions: true, volumeAdaptationOn: false, videoSurface: true), .moviePlayback)
        XCTAssertEqual(InterruptionPolicy.sessionMode(pauseForInterruptions: false, volumeAdaptationOn: true, videoSurface: false), .standard,
                       "Duck wins over Volume adaptation's speech mode")
        XCTAssertEqual(InterruptionPolicy.sessionMode(pauseForInterruptions: false, volumeAdaptationOn: false, videoSurface: true), .moviePlayback)
    }

    func testResume() {
        XCTAssertTrue(InterruptionPolicy.shouldResume(wasPlayingWhenBegan: true, systemShouldResume: true, userActedSince: false))
        XCTAssertFalse(InterruptionPolicy.shouldResume(wasPlayingWhenBegan: false, systemShouldResume: true, userActedSince: false))
        XCTAssertFalse(InterruptionPolicy.shouldResume(wasPlayingWhenBegan: true, systemShouldResume: false, userActedSince: false))
        XCTAssertFalse(InterruptionPolicy.shouldResume(wasPlayingWhenBegan: true, systemShouldResume: true, userActedSince: true))
    }
}
