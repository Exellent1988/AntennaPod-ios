import Combine
import PodcastCore
import XCTest
@testable import AntennaPod

/// ANALYSIS ONLY (no production change): cost of one progress persist (every 5 s on the 0.5 s
/// tick, PlaybackService.persistProgress → PodcastStore.saveProgress) with a 6,500-episode library.
/// Prints `MEASURE` lines; the final assertion is intentionally strict (red = budget exceeded).
@MainActor
final class ZTick6500MeasurementTests: PlaybackFixtureTestCase {
    private var savedFeeds: [PodcastFeed] = []

    override func setUp() async throws {
        try await super.setUp()
        savedFeeds = store.feeds
    }

    override func tearDown() async throws {
        store.feeds = savedFeeds
        try await super.tearDown()
    }

    private func ms(_ block: () -> Void) -> Double {
        let t = CFAbsoluteTimeGetCurrent(); block(); return (CFAbsoluteTimeGetCurrent() - t) * 1000
    }

    func testPersistTickCostWith6500Episodes() throws {
        settings.historySizeLimit = .unlimited
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var feeds: [PodcastFeed] = []
        var states: [String: EpisodePlaybackState] = [:]
        for f in 0..<65 {
            let url = "https://tick6500.example/\(f)"
            var eps: [PodcastEpisode] = []
            for e in 0..<100 {
                var ep = PodcastEpisode(id: "\(url)#\(e)", title: "Episode \(f)-\(e)", downloadUrl: "https://e/\(f)/\(e).mp3",
                                        mimeType: "audio/mpeg", durationSeconds: 3600)
                ep.pubDateEpochMs = now - Int64(e) * 86_400_000
                eps.append(ep)
                if e % 3 == 0 {
                    states[ep.id] = EpisodePlaybackState(positionSeconds: Double(e * 10), durationSeconds: 3600, isPlayed: e % 2 == 0,
                                                         updatedAtEpochMs: now - Int64(e), lastPlayedAtEpochMs: now - Int64(e))
                }
            }
            feeds.append(PodcastFeed(id: UUID(), title: "Tick \(f)", feedUrl: url, siteLink: nil, imageUrl: nil, descriptionText: nil,
                                     author: nil, language: nil, fundingUrl: nil, fundingLabel: nil, categories: [], isLocked: false,
                                     lockedOwner: nil, podcastGuid: nil, episodes: eps))
        }
        let tFeeds = ms { store.feeds = feeds }
        let tStates = ms { store.playbackStates = states }
        let target = feeds[0].episodes[1].id

        var willChange = 0
        let sub = store.objectWillChange.sink { willChange += 1 }
        defer { sub.cancel() }

        var save: [Double] = [], inbox: [Double] = [], history: [Double] = [], all: [Double] = [],
            cont: [Double] = [], remaining: [Double] = [], stats: [Double] = [], encode: [Double] = []
        for i in 0..<10 {
            save.append(ms { store.saveProgress(episodeId: target, positionSeconds: Double(100 + i * 5), durationSeconds: 3600,
                                                listenedWallDelta: 5, listenedMediaDelta: 5) })
            // What views observing the store recompute after the objectWillChange of that save:
            inbox.append(ms { _ = store.inboxEpisodes })
            history.append(ms { _ = store.historyEpisodes })
            all.append(ms { _ = store.allEpisodes })
            cont.append(ms { _ = store.continueListeningEpisodes })
            remaining.append(ms { _ = store.unplayedRemainingByFeedId() })
            stats.append(ms { _ = store.listeningStatistics(in: .allTime) })
            encode.append(ms { _ = try? JSONEncoder().encode(store.playbackStates) })
        }
        func avg(_ a: [Double]) -> String { String(format: "%.1f", a.reduce(0, +) / Double(a.count)) }
        func mx(_ a: [Double]) -> String { String(format: "%.1f", a.max() ?? 0) }
        print("MEASURE setup feeds=\(Int(tFeeds))ms states=\(Int(tStates))ms episodes=6500 states=\(states.count)")
        print("MEASURE objectWillChange per saveProgress = \(Double(willChange) / 10)")
        for (n, a) in [("saveProgress", save), ("inboxEpisodes(after save)", inbox), ("historyEpisodes(cached?)", history),
                       ("allEpisodes", all), ("continueListening", cont), ("unplayedRemainingByFeedId", remaining),
                       ("listeningStatistics", stats), ("JSON encode playbackStates (bg queue)", encode)] {
            print("MEASURE \(n): avg \(avg(a)) ms, max \(mx(a)) ms")
        }
        // Budget: one persist + the Inbox rebuild it triggers must fit in one 60 Hz frame.
        let perPersist = (save.reduce(0, +) + inbox.reduce(0, +)) / 10
        XCTAssertLessThan(perPersist, 16, "persist tick main-thread cost \(perPersist) ms with 6,500 episodes")
    }
}
