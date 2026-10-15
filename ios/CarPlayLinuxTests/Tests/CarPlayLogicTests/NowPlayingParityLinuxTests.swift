import XCTest
@testable import CarPlayLogic

/// Android Auto Now Playing parity (PlaybackService media session) for the pure NowPlayingLogic rules.
final class NowPlayingParityLinuxTests: XCTestCase {
    func testSpeedCycleMatchesAndroidCustomAction() {
        let p: [Float] = [1.0, 1.25, 1.5]
        XCTAssertEqual(NowPlayingLogic.nextSpeedPreset(presets: p, current: 1.0), 1.25)
        XCTAssertEqual(NowPlayingLogic.nextSpeedPreset(presets: p, current: 1.5), 1.0, "Wraps")
        XCTAssertEqual(NowPlayingLogic.nextSpeedPreset(presets: p, current: 2.0), 1.0, "Not a preset → first")
        XCTAssertEqual(NowPlayingLogic.nextSpeedPreset(presets: p, current: 1.2500001), 1.5, "Float tolerance")
        XCTAssertNil(NowPlayingLogic.nextSpeedPreset(presets: [1.5], current: 1.0), "One preset: no change")
        XCTAssertNil(NowPlayingLogic.nextSpeedPreset(presets: [], current: 1.0))
    }

    func testSleepToggleUsesLastUsedTimer() {
        XCTAssertEqual(NowPlayingLogic.sleepToggleTarget(episodesKind: false, lastMinutes: 40, lastEpisodes: 3), .minutes(40))
        XCTAssertEqual(NowPlayingLogic.sleepToggleTarget(episodesKind: true, lastMinutes: 40, lastEpisodes: 3), .episodes(3))
        XCTAssertEqual(NowPlayingLogic.sleepToggleTarget(episodesKind: false, lastMinutes: 0, lastEpisodes: 0), .minutes(15))
        XCTAssertEqual(NowPlayingLogic.sleepToggleTarget(episodesKind: true, lastMinutes: 0, lastEpisodes: 0), .episodes(1))
    }

    func testSkipIntervalsDefaultLikeAndroidPrefs() {
        let d = NowPlayingLogic.skipIntervals(rewind: 0, forward: .nan)
        XCTAssertEqual(d.back, 10); XCTAssertEqual(d.forward, 30)
        let c = NowPlayingLogic.skipIntervals(rewind: 5, forward: 60)
        XCTAssertEqual(c.back, 5); XCTAssertEqual(c.forward, 60)
    }

    func testTrackActionsInCar() {
        XCTAssertEqual(NowPlayingLogic.nextTrackAction(inCar: true), .skipEpisode)
        XCTAssertEqual(NowPlayingLogic.previousTrackAction(inCar: true), .rewind)
        XCTAssertEqual(NowPlayingLogic.nextTrackAction(inCar: false), .hardwareButton)
    }

    func testNextChapterFallsBackToSkipOnLastChapter() {
        XCTAssertEqual(NowPlayingLogic.nextChapterStart(starts: [0, 60, 120], at: 70), 120)
        XCTAssertNil(NowPlayingLogic.nextChapterStart(starts: [0, 60, 120], at: 130))
        XCTAssertNil(NowPlayingLogic.nextChapterStart(starts: [], at: 0))
    }

    func testButtonOrder() {
        XCTAssertEqual(NowPlayingLogic.nowPlayingButtons(hasChapters: true), [.rate, .sleepTimer, .nextChapter, .skipEpisode])
        XCTAssertEqual(NowPlayingLogic.nowPlayingButtons(hasChapters: false), [.rate, .sleepTimer, .skipEpisode])
    }
}
