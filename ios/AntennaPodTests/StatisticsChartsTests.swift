import PodcastCore
import XCTest
@testable import AntennaPod

/// Statistics charts data: monthly bars match the yearly total.
@MainActor
final class StatisticsChartsTests: PlaybackFixtureTestCase {
    func testMonthlyBarsSumToYear() {
        settings.statisticsResetAtEpochMs = 0
        settings.statisticsIncludeMarkedPlayed = true
        let url = "https://charts.example/feed"
        let f = PodcastFeed(id: UUID(), title: "Charts", feedUrl: url, siteLink: nil, imageUrl: nil, descriptionText: nil,
                            author: nil, language: nil, fundingUrl: nil, fundingLabel: nil, categories: [], isLocked: false,
                            lockedOwner: nil, podcastGuid: nil,
                            episodes: ["a", "b"].map { PodcastEpisode(id: "\(url)#\($0)", title: $0, downloadUrl: "https://e/\($0).mp3",
                                                                    mimeType: "audio/mpeg", durationSeconds: 120) })
        store.feeds = [f]
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let st = EpisodePlaybackState(positionSeconds: 0, durationSeconds: 120, isPlayed: true, updatedAtEpochMs: now, lastPlayedAtEpochMs: now)
        store.playbackStates = [f.episodes[0].id: st, f.episodes[1].id: st]
        let year = Calendar.current.component(.year, from: Date())
        let months = store.monthlyListening(year: year)
        XCTAssertEqual(months.count, 12)
        XCTAssertEqual(months.reduce(0, +), store.yearlyListening().first?.seconds ?? -1, accuracy: 0.5)
        XCTAssertEqual(months[Calendar.current.component(.month, from: Date()) - 1], 240, accuracy: 0.5)
        XCTAssertEqual(store.monthlyListening(year: year - 5).reduce(0, +), 0)
    }
}
