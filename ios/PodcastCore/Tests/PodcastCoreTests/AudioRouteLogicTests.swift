import XCTest
@testable import PodcastCore

final class AudioRouteLogicTests: XCTestCase {
    func testRouteKind() {
        XCTAssertEqual(AudioRouteKind.kind(ofOutputPorts: ["Headphones"]), .wired)
        XCTAssertEqual(AudioRouteKind.kind(ofOutputPorts: ["USBAudio"]), .wired)
        XCTAssertEqual(AudioRouteKind.kind(ofOutputPorts: ["BluetoothA2DPOutput"]), .bluetooth)
        XCTAssertEqual(AudioRouteKind.kind(ofOutputPorts: ["BluetoothHFP"]), .bluetooth)
        XCTAssertEqual(AudioRouteKind.kind(ofOutputPorts: ["Speaker"]), .other)
        XCTAssertEqual(AudioRouteKind.kind(ofOutputPorts: ["CarAudio"]), .other)
        XCTAssertEqual(AudioRouteKind.kind(ofOutputPorts: ["AirPlay"]), .other)
        XCTAssertEqual(AudioRouteKind.kind(ofOutputPorts: []), .other)
    }

    func testResumeNeedsOurUnplugPauseAndTheMatchingSetting() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let soon = t0.addingTimeInterval(60)
        XCTAssertTrue(ReconnectResumePolicy.shouldResume(pausedByUnplugAt: t0, now: soon, newRoute: .wired,
                                                         resumeOnHeadphones: true, resumeOnBluetooth: false))
        XCTAssertFalse(ReconnectResumePolicy.shouldResume(pausedByUnplugAt: t0, now: soon, newRoute: .bluetooth,
                                                          resumeOnHeadphones: true, resumeOnBluetooth: false),
                       "Android default: Bluetooth reconnect off")
        XCTAssertTrue(ReconnectResumePolicy.shouldResume(pausedByUnplugAt: t0, now: soon, newRoute: .bluetooth,
                                                         resumeOnHeadphones: false, resumeOnBluetooth: true))
        XCTAssertFalse(ReconnectResumePolicy.shouldResume(pausedByUnplugAt: nil, now: soon, newRoute: .wired,
                                                          resumeOnHeadphones: true, resumeOnBluetooth: true),
                       "User pause / never playing → no resume")
        XCTAssertFalse(ReconnectResumePolicy.shouldResume(pausedByUnplugAt: t0, now: soon, newRoute: .other,
                                                          resumeOnHeadphones: true, resumeOnBluetooth: true))
    }

    func testWindow() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let limit = ReconnectResumePolicy.resumeWindowSeconds
        XCTAssertTrue(ReconnectResumePolicy.shouldResume(pausedByUnplugAt: t0, now: t0.addingTimeInterval(limit),
                                                         newRoute: .wired, resumeOnHeadphones: true, resumeOnBluetooth: true))
        XCTAssertFalse(ReconnectResumePolicy.shouldResume(pausedByUnplugAt: t0, now: t0.addingTimeInterval(limit + 1),
                                                          newRoute: .wired, resumeOnHeadphones: true, resumeOnBluetooth: true))
        XCTAssertFalse(ReconnectResumePolicy.shouldResume(pausedByUnplugAt: t0, now: t0.addingTimeInterval(-1),
                                                          newRoute: .wired, resumeOnHeadphones: true, resumeOnBluetooth: true))
    }
}

final class DisconnectPausePolicyTests: XCTestCase {
    func testPauseOnlyWhenOnAndPlaying() {
        XCTAssertTrue(DisconnectPausePolicy.defaultPauseOnDisconnect)
        XCTAssertTrue(DisconnectPausePolicy.shouldPause(pauseOnDisconnect: true, isPlaying: true))
        XCTAssertFalse(DisconnectPausePolicy.shouldPause(pauseOnDisconnect: false, isPlaying: true))
        XCTAssertFalse(DisconnectPausePolicy.shouldPause(pauseOnDisconnect: true, isPlaying: false))
    }
}
