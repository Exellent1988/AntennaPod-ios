import PodcastCore
import XCTest
@testable import AntennaPod

/// End-to-end playback through the real `PlaybackService` / `AVPlayer` (see `PlaybackFixtureTestCase`):
/// continuous advance on natural end, manual skip, Skip ending, the episode sleep timer, and that the
/// playback state feeding gpodder sync looks the same on every path.
@MainActor
final class PlaybackEndToEndTests: PlaybackFixtureTestCase {
    // MARK: (a) natural end

    func testNaturalEndAdvancesQueueUnderContinuousPlayback() async throws {
        XCTAssertTrue(playback.play(episode: episodes[0]))
        try await waitFor("episode 2 playing after natural end of 1", timeout: 12) {
            self.playback.currentEpisode?.id == self.episodes[1].id && self.playback.isPlaying
        }
        assertFinished(episodes[0])
        XCTAssertFalse(store.queue.contains { $0.id == episodes[0].id }, "Finished episode leaves the queue")
    }

    func testNaturalEndWithContinuousOffStops() async throws {
        settings.continuousPlaybackMode = .off
        XCTAssertTrue(playback.play(episode: episodes[0]))
        try await waitFor("player idle after episode 1", timeout: 12) { self.playback.currentEpisode == nil }
        assertFinished(episodes[0])
        XCTAssertFalse(store.isPlayed(episodes[1].id))
    }

    // MARK: (b) manual skip

    func testManualSkipToNextEpisodeAdvances() async throws {
        XCTAssertTrue(playback.play(episode: episodes[0]))
        try await waitFor("episode 1 past 1 s", timeout: 8) { self.playback.positionSeconds > 1 }
        playback.skipToNextEpisode()
        XCTAssertEqual(playback.currentEpisode?.id, episodes[1].id)
        try await waitFor("episode 2 playing", timeout: 8) { self.playback.isPlaying }
        assertFinished(episodes[0])
    }

    /// Regression: skipping before the time observer has reported a duration used to save
    /// duration 0, so gpodder sync dropped the played action for that episode.
    func testImmediateSkipStillRecordsDurationForSync() async throws {
        XCTAssertTrue(playback.play(episode: episodes[0]))
        playback.skipToNextEpisode()
        assertFinished(episodes[0])
        let ref = GpodderSyncLogic.EpisodeRef(episodeId: episodes[0].id, feedUrl: "https://example.invalid/feed.xml",
                                              mediaUrl: "https://example.invalid/a.mp3")
        let actions = GpodderSyncLogic.localActions(refs: [ref], localStates: store.playbackStates,
                                                    sinceMs: 0, deviceId: "test")
        XCTAssertEqual(actions.first?.position, 3)
        XCTAssertEqual(actions.first?.total, 3)
    }

    // MARK: (c) Skip ending

    func testSkipEndingAdvancesEarly() async throws {
        settings.skipOutroSeconds = 1
        XCTAssertTrue(playback.play(episode: episodes[0]))
        try await waitFor("episode 2 after Skip ending", timeout: 12) {
            self.playback.currentEpisode?.id == self.episodes[1].id
        }
        assertFinished(episodes[0])
    }

    // MARK: (d) episode sleep timer

    func testEpisodeSleepTimerCountsDownAndStopsWithoutAdvancing() async throws {
        XCTAssertTrue(playback.play(episode: episodes[0]))
        playback.setSleepTimer(episodes: 3, remember: false)
        XCTAssertEqual(playback.sleepTimerEpisodeCounter?.remaining, 3)
        // Episode 1 ends naturally → 2 left, episode 2 plays.
        try await waitFor("episode 2 after natural end", timeout: 12) {
            self.playback.currentEpisode?.id == self.episodes[1].id
        }
        XCTAssertEqual(playback.sleepTimerEpisodeCounter?.remaining, 2)
        // Manual skip on episode 2 → 1 left (last episode), episode 3 plays.
        playback.skipToNextEpisode()
        XCTAssertEqual(playback.currentEpisode?.id, episodes[2].id)
        XCTAssertEqual(playback.sleepTimerEpisodeCounter?.remaining, 1)
        XCTAssertTrue(playback.sleepTimerEpisodeCounter?.isOnLastEpisode == true)
        // Put a 4th episode in the queue: the timer must stop instead of advancing to it.
        let extra = episodes[0]
        store.markUnplayed(extra.id)
        store.queue.append(extra)
        try await waitFor("player stopped after the 3rd episode", timeout: 12) {
            self.playback.currentEpisode == nil
        }
        XCTAssertFalse(playback.isSleepTimerActive)
        XCTAssertNil(playback.sleepTimerEpisodeCounter)
        XCTAssertFalse(playback.isPlaying)
        assertFinished(episodes[1])
        assertFinished(episodes[2])
        XCTAssertFalse(store.isPlayed(extra.id), "Did not advance into the next queue item")
    }

    func testEpisodeSleepTimerStopsWhenQueueRunsOutFirst() async throws {
        store.queue = [episodes[0]]
        XCTAssertTrue(playback.play(episode: episodes[0]))
        playback.setSleepTimer(episodes: 3, remember: false)
        try await waitFor("player idle", timeout: 12) { self.playback.currentEpisode == nil }
        XCTAssertFalse(playback.isSleepTimerActive, "Nothing left to play: the timer is finished too")
        assertFinished(episodes[0])
    }

    // MARK: (e) gpodder-facing state

    /// Every path that finishes an episode leaves the same playback state (played, position
    /// reset, real duration) and therefore the same gpodder `play` action (position == total)
    /// as a natural end; a pause in the middle still saves the position.
    func testSyncStateIsTheSameForAllFinishPaths() async throws {
        // Natural end (unchanged pre-existing path) is the reference.
        XCTAssertTrue(playback.play(episode: episodes[0]))
        try await waitFor("natural end", timeout: 12) { self.playback.currentEpisode?.id == self.episodes[1].id }
        // Episode 2: manual skip under an episode sleep timer.
        playback.setSleepTimer(episodes: 2, remember: false)
        try await waitFor("episode 2 past 1 s", timeout: 8) { self.playback.positionSeconds > 1 }
        playback.skipToNextEpisode()
        // Episode 3: pause mid-way → position saved, not played.
        try await waitFor("episode 3 past 1 s", timeout: 8) {
            self.playback.currentEpisode?.id == self.episodes[2].id && self.playback.positionSeconds > 1
        }
        playback.togglePlayPause()
        let paused = store.playbackState(for: episodes[2].id)
        XCTAssertFalse(paused.isPlayed)
        XCTAssertGreaterThan(paused.positionSeconds, 0.9)

        let reference = store.playbackState(for: episodes[0].id)
        let skipped = store.playbackState(for: episodes[1].id)
        XCTAssertEqual(skipped.isPlayed, reference.isPlayed)
        XCTAssertEqual(skipped.positionSeconds, reference.positionSeconds)
        XCTAssertEqual(skipped.durationSeconds, reference.durationSeconds, accuracy: 0.2)
        XCTAssertNotNil(skipped.lastPlayedAtEpochMs)

        let refs = episodes.map {
            GpodderSyncLogic.EpisodeRef(episodeId: $0.id, feedUrl: "https://example.invalid/feed.xml",
                                        mediaUrl: "https://example.invalid/\($0.id).mp3")
        }
        let actions = GpodderSyncLogic.localActions(refs: refs, localStates: store.playbackStates,
                                                    sinceMs: 0, deviceId: "test")
        let byId = Dictionary(uniqueKeysWithValues: actions.map { ($0.guid ?? "", $0) })
        let natural = try XCTUnwrap(byId[episodes[0].id])
        let skip = try XCTUnwrap(byId[episodes[1].id])
        let mid = try XCTUnwrap(byId[episodes[2].id])
        XCTAssertEqual(natural.action, "play")
        XCTAssertEqual(natural.position, natural.total, "Played → position == total")
        XCTAssertEqual(skip.action, natural.action)
        XCTAssertEqual(skip.position, natural.position)
        XCTAssertEqual(skip.total, natural.total)
        XCTAssertLessThan(mid.position ?? 0, mid.total ?? 0)
        XCTAssertGreaterThanOrEqual(mid.position ?? 0, 1)
    }

}
