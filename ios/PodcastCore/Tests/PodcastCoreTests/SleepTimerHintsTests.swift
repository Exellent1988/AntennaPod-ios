import PodcastCore
import XCTest

final class SleepTimerHintsTests: XCTestCase {
    func testEpisodesWithoutContinuousPlayback() {
        XCTAssertEqual(SleepTimerHints.hint(kind: .episodes, continuousPlayback: false, selectedEpisodes: 3,
                                            selectedMinutes: nil, queueRemaining: 10, episodeRemainingSeconds: nil),
                       .episodesWithoutContinuousPlayback)
        XCTAssertFalse(SleepTimerHints.canStart(kind: .episodes, continuousPlayback: false))
        XCTAssertFalse(SleepTimerHints.showsOptions(kind: .episodes, continuousPlayback: false))
        XCTAssertTrue(SleepTimerHints.canStart(kind: .clock, continuousPlayback: false))
        XCTAssertTrue(SleepTimerHints.canStart(kind: .episodes, continuousPlayback: true))
    }

    func testEpisodesExceedQueue() {
        XCTAssertEqual(SleepTimerHints.hint(kind: .episodes, continuousPlayback: true, selectedEpisodes: 3,
                                            selectedMinutes: nil, queueRemaining: 2, episodeRemainingSeconds: nil),
                       .episodesExceedQueue(remaining: 2))
        XCTAssertNil(SleepTimerHints.hint(kind: .episodes, continuousPlayback: true, selectedEpisodes: 2,
                                          selectedMinutes: nil, queueRemaining: 2, episodeRemainingSeconds: nil))
        XCTAssertNil(SleepTimerHints.hint(kind: .episodes, continuousPlayback: true, selectedEpisodes: 9,
                                          selectedMinutes: nil, queueRemaining: nil, episodeRemainingSeconds: nil))
    }

    func testClockExceedsEpisodeOnlyWithoutContinuousPlayback() {
        XCTAssertEqual(SleepTimerHints.hint(kind: .clock, continuousPlayback: false, selectedEpisodes: 1,
                                            selectedMinutes: 30, queueRemaining: nil, episodeRemainingSeconds: 600),
                       .timerExceedsEpisode(minutesLeft: 10))
        XCTAssertNil(SleepTimerHints.hint(kind: .clock, continuousPlayback: true, selectedEpisodes: 1,
                                          selectedMinutes: 30, queueRemaining: nil, episodeRemainingSeconds: 600))
        XCTAssertNil(SleepTimerHints.hint(kind: .clock, continuousPlayback: false, selectedEpisodes: 1,
                                          selectedMinutes: 5, queueRemaining: nil, episodeRemainingSeconds: 600))
        XCTAssertNil(SleepTimerHints.hint(kind: .clock, continuousPlayback: false, selectedEpisodes: 1,
                                          selectedMinutes: 30, queueRemaining: nil, episodeRemainingSeconds: nil))
    }

    func testShakeOnlyForClock() {
        XCTAssertTrue(SleepTimerHints.showsShakeToReset(kind: .clock))
        XCTAssertFalse(SleepTimerHints.showsShakeToReset(kind: .episodes))
    }

    func testMostOfDayAndConfirmation() {
        XCTAssertFalse(SleepTimerHints.isMostOfDay(fromHour: 22, toHour: 6))  // 8 h
        XCTAssertFalse(SleepTimerHints.isMostOfDay(fromHour: 8, toHour: 20))  // 12 h, not > 12
        XCTAssertTrue(SleepTimerHints.isMostOfDay(fromHour: 8, toHour: 21))
        XCTAssertTrue(SleepTimerHints.isMostOfDay(fromHour: 5, toHour: 5))    // always
        XCTAssertTrue(SleepTimerHints.needsAlwaysEpisodeConfirmation(autoEnable: true, kind: .episodes, fromHour: 0, toHour: 0))
        XCTAssertFalse(SleepTimerHints.needsAlwaysEpisodeConfirmation(autoEnable: true, kind: .clock, fromHour: 0, toHour: 0))
        XCTAssertFalse(SleepTimerHints.needsAlwaysEpisodeConfirmation(autoEnable: false, kind: .episodes, fromHour: 0, toHour: 0))
        XCTAssertFalse(SleepTimerHints.needsAlwaysEpisodeConfirmation(autoEnable: true, kind: .episodes, fromHour: 22, toHour: 6))
    }

    func testRemainingQueueSize() {
        XCTAssertEqual(SleepTimerHints.remainingQueueSize(queueIds: ["a", "b", "c"], currentId: "a"), 2)
        XCTAssertEqual(SleepTimerHints.remainingQueueSize(queueIds: ["a", "b", "c"], currentId: "c"), 0)
        XCTAssertEqual(SleepTimerHints.remainingQueueSize(queueIds: ["a", "b"], currentId: "x"), 2)
        XCTAssertEqual(SleepTimerHints.remainingQueueSize(queueIds: [], currentId: nil), 0)
    }
}
