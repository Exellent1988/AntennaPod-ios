import Combine
import XCTest
@testable import AntennaPod

/// Crash ~1 min after playback start with ~6,500 episodes (cpu_resource_fatal, SwiftUI updates on
/// main). Android parity: list rows show stored progress (refreshed on pause / stop / episode
/// change); only the mini player / player screen follow PlaybackPositionEvent per tick.
@MainActor
final class StaticListProgressTests: XCTestCase {
    private var store: PodcastStore!
    private var playback: PlaybackService!
    private var savedFeeds: [PodcastFeed] = []
    private var savedStates: [String: EpisodePlaybackState] = [:]

    override func setUp() async throws {
        store = PodcastStore()
        savedFeeds = store.feeds
        savedStates = store.playbackStates
        playback = PlaybackService()
        playback.store = store
        store.playback = playback
        store.feeds = Self.seed()
    }

    override func tearDown() async throws {
        store.feeds = savedFeeds
        store.playbackStates = savedStates
        store.playback = nil
        playback.store = nil
    }

    /// 65 feeds × 100 = 6,500 episodes.
    static func seed() -> [PodcastFeed] {
        (0..<65).map { f in
            PodcastFeed(id: UUID(), title: "F\(f)", feedUrl: "https://perf.invalid/\(f)/rss", siteLink: nil, imageUrl: nil,
                        descriptionText: nil, author: nil, language: nil, fundingUrl: nil, fundingLabel: nil, categories: [],
                        isLocked: false, lockedOwner: nil, podcastGuid: nil,
                        episodes: (0..<100).map { e in
                            var ep = PodcastEpisode(id: "slp-\(f)-\(e)", title: "E\(e)", downloadUrl: "https://perf.invalid/\(f)/\(e).mp3",
                                                    mimeType: "audio/mpeg", durationSeconds: 1800)
                            ep.pubDateEpochMs = Int64(f * 100 + e) * 60_000
                            return ep
                        })
        }
    }

    /// One minute of playback (120 ticks at 0.5 s, a progress save every 5 s like
    /// `PlaybackService.persistProgress`) must not invalidate list screens per tick.
    func testPlaybackTicksDoNotInvalidateListsAndStoredProgressRefreshesOnPause() {
        let now = NowPlayingListState(playback: playback, store: store)
        let ep = store.feeds[0].episodes[0]
        store.saveProgress(episodeId: ep.id, positionSeconds: 5, durationSeconds: 1800)
        now.updateNowPlaying(episodeId: ep.id, isPlaying: true)
        var listInvalidations = 0
        let s1 = now.objectWillChange.sink { listInvalidations += 1 }
        let s2 = store.objectWillChange.sink { listInvalidations += 1 }
        defer { s1.cancel(); s2.cancel() }
        for tick in 1...120 {
            let pos = 5 + Double(tick) * 0.5
            playback.positionSeconds = pos
            playback.durationSeconds = 1800
            if tick % 10 == 0 {
                store.saveProgress(episodeId: ep.id, positionSeconds: pos, durationSeconds: 1800, listenedWallDelta: 5, listenedMediaDelta: 5)
            }
        }
        print("STATIC-LIST invalidations over 120 ticks: \(listInvalidations)")
        XCTAssertEqual(listInvalidations, 0, "list-facing state must not change per playback tick")
        XCTAssertEqual(store.positionSeconds(for: ep.id), 65, accuracy: 0.01, "progress is still saved while playing")

        now.updateNowPlaying(episodeId: ep.id, isPlaying: false)
        XCTAssertGreaterThanOrEqual(listInvalidations, 1, "pause publishes the stored progress once")
        XCTAssertEqual(now.storedPositionSeconds, 65, accuracy: 0.01)
    }

    /// Feed counters / per-feed remaining are computed once per data change, not per redraw.
    func testUnplayedRemainingIsCachedUntilDataChanges() {
        let before = store.unplayedRemainingComputeCount
        let a = store.unplayedRemainingByFeedId()
        for _ in 0..<20 { _ = store.unplayedRemainingByFeedId() }
        XCTAssertEqual(store.unplayedRemainingComputeCount - before, 1, "20 redraws reuse one computation")
        XCTAssertEqual(a.count, 65)
        store.markPlayed(store.feeds[0].episodes[1].id, removeFromQueue: false)
        let b = store.unplayedRemainingByFeedId()
        XCTAssertEqual(store.unplayedRemainingComputeCount - before, 2, "data change recomputes")
        XCTAssertEqual(b[store.feeds[0].id]?.unplayedCount, 99)
    }

    /// Downloaded lookup must not scan the whole downloads list per row.
    func testDownloadedLookupUsesIndex() {
        let downloads = DownloadService()
        XCTAssertNil(downloads.downloadedItem(forEpisodeId: "slp-none"))
    }
}
