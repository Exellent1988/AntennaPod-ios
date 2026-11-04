import PodcastCore
import XCTest
@testable import AntennaPod

/// Android `SleepTimerDialog` hints on the real PlaybackService, settings and queue.
@MainActor
final class SleepTimerHintsParityTests: PlaybackFixtureTestCase {
    func testEpisodeTimerExceedsQueue() async throws {
        XCTAssertTrue(playback.play(episode: episodes[0]))
        try await waitFor("current episode", timeout: 5) { self.playback.currentEpisode?.id == self.episodes[0].id }
        XCTAssertEqual(playback.sleepTimerQueueRemaining, 2)
        XCTAssertNil(playback.sleepTimerHint(kind: .episodes, episodes: 2, minutes: nil))
        let hint = try XCTUnwrap(playback.sleepTimerHint(kind: .episodes, episodes: 5, minutes: nil))
        XCTAssertEqual(hint, .episodesExceedQueue(remaining: 2))
        XCTAssertTrue(PlaybackService.sleepTimerHintText(hint).contains("2"))
    }

    func testEpisodeTimerWithoutContinuousPlayback() {
        settings.continuousPlaybackMode = .off
        XCTAssertFalse(playback.sleepTimerContinuousPlayback)
        XCTAssertEqual(playback.sleepTimerHint(kind: .episodes, episodes: 1, minutes: nil), .episodesWithoutContinuousPlayback)
        XCTAssertFalse(SleepTimerHints.canStart(kind: .episodes, continuousPlayback: playback.sleepTimerContinuousPlayback))
    }

    func testClockTimerExceedsEpisodeWithoutContinuousPlayback() async throws {
        settings.continuousPlaybackMode = .off
        XCTAssertTrue(playback.play(episode: episodes[0]))
        try await waitFor("duration", timeout: 5) { self.playback.durationSeconds > 0 }
        // 3 s fixture: any minute timer is longer → 0 minutes left.
        XCTAssertEqual(playback.sleepTimerHint(kind: .clock, episodes: 1, minutes: 1), .timerExceedsEpisode(minutesLeft: 0))
        settings.continuousPlaybackMode = .queue
        XCTAssertNil(playback.sleepTimerHint(kind: .clock, episodes: 1, minutes: 1))
    }

    func testSamePodcastModeHasNoQueueHint() {
        settings.continuousPlaybackMode = .samePodcast
        XCTAssertNil(playback.sleepTimerQueueRemaining)
        XCTAssertNil(playback.sleepTimerHint(kind: .episodes, episodes: 20, minutes: nil))
    }
}
