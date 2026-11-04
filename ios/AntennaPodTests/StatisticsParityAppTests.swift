import PodcastCore
import XCTest
@testable import AntennaPod

/// Android Statistics parity: Include marked as played, Years, Downloads per podcast.
@MainActor
final class StatisticsParityAppTests: PlaybackFixtureTestCase {
    private func seed() -> PodcastFeed {
        let url = "https://stats-parity.example/feed"
        let f = PodcastFeed(id: UUID(), title: "Stats", feedUrl: url, siteLink: nil, imageUrl: nil, descriptionText: nil,
                            author: nil, language: nil, fundingUrl: nil, fundingLabel: nil, categories: [], isLocked: false,
                            lockedOwner: nil, podcastGuid: nil,
                            episodes: ["a", "b"].map { PodcastEpisode(id: "\(url)#\($0)", title: $0, downloadUrl: "https://e/\($0).mp3",
                                                                    mimeType: "audio/mpeg", durationSeconds: 60) })
        store.feeds = [f]
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var marked = EpisodePlaybackState(positionSeconds: 0, durationSeconds: 60, isPlayed: true, updatedAtEpochMs: now, lastPlayedAtEpochMs: now)
        var listened = marked
        listened.listenedWallSeconds = 30
        marked.listenedWallSeconds = nil
        store.playbackStates = [f.episodes[0].id: marked, f.episodes[1].id: listened]
        return f
    }

    func testIncludeMarkedPlayedChangesTotalsAndYears() {
        settings.statisticsResetAtEpochMs = 0
        _ = seed()
        settings.statisticsIncludeMarkedPlayed = true
        XCTAssertEqual(store.listeningStatistics(in: .allTime).approximateListenedSeconds, 90, accuracy: 0.5)
        settings.statisticsIncludeMarkedPlayed = false
        XCTAssertEqual(store.listeningStatistics(in: .allTime).approximateListenedSeconds, 30, accuracy: 0.5)
        let years = store.yearlyListening()
        XCTAssertEqual(years.map(\.year), [Calendar.current.component(.year, from: Date())])
        XCTAssertEqual(years.first?.seconds ?? 0, 30, accuracy: 0.5)
    }

    func testSettingPersistsAndIsInBackup() throws {
        settings.statisticsIncludeMarkedPlayed = false
        XCTAssertFalse(AppSettings().statisticsIncludeMarkedPlayed)
        let data = try JSONEncoder().encode(settings.backupSnapshot())
        settings.statisticsIncludeMarkedPlayed = true
        settings.applyBackupSnapshot(try JSONDecoder().decode(AppSettingsBackupSnapshot.self, from: data))
        XCTAssertFalse(settings.statisticsIncludeMarkedPlayed)
    }
}
