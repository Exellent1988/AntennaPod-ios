import PodcastCore
import XCTest
@testable import AntennaPod

/// Android EpisodeItemViewHolder: lists honour Show remaining time + Remaining time respects speed.
@MainActor
final class ListRemainingTimeTests: PlaybackFixtureTestCase {
    func testRowCaptionUsesSettingsAndPodcastSpeed() {
        let savedFeeds = store.feeds
        defer { store.feeds = savedFeeds }
        let ep = PodcastEpisode(id: "lrt-\(UUID().uuidString.prefix(6))", title: "LRT", downloadUrl: "https://lrt.example/e.mp3",
                                mimeType: "audio/mpeg", durationSeconds: 3600)
        let feed = PodcastFeed(id: UUID(), title: "LRT", feedUrl: "https://lrt.example/rss", siteLink: nil, imageUrl: nil,
                               descriptionText: nil, author: nil, language: nil, fundingUrl: nil, fundingLabel: nil,
                               categories: [], isLocked: false, lockedOwner: nil, podcastGuid: nil, episodes: [ep])
        store.feeds = savedFeeds + [feed]
        defer { store.setFeedSettings(.default, for: feed.id) }
        store.updateFeedSettings(for: feed.id) { $0.playbackSpeed = 1.5 }
        settings.defaultPlaybackSpeed = 1.0

        func caption() -> String? {
            EpisodeListTimeCaption.value(durationSeconds: 3600, positionSeconds: 600, isPlayed: false,
                                         showRemaining: settings.showRemainingTime,
                                         respectsSpeed: settings.remainingTimeRespectsSpeed,
                                         speed: store.resolvedPlaybackSpeedForRemaining(for: ep)).map(EpisodeListTimeCaption.format)
        }
        settings.showRemainingTime = false; settings.remainingTimeRespectsSpeed = false
        XCTAssertEqual(caption(), "1:00:00")
        settings.showRemainingTime = true
        XCTAssertEqual(caption(), "\u{2212}50:00")
        settings.remainingTimeRespectsSpeed = true
        XCTAssertEqual(caption(), "\u{2212}33:20", "per-podcast 1.5× speed")
    }

    func testListSettingsInBackup() throws {
        settings.showRemainingTime = true
        settings.remainingTimeRespectsSpeed = true
        let data = try JSONEncoder().encode(settings.backupSnapshot())
        settings.showRemainingTime = false
        settings.remainingTimeRespectsSpeed = false
        settings.applyBackupSnapshot(try JSONDecoder().decode(AppSettingsBackupSnapshot.self, from: data))
        XCTAssertTrue(settings.showRemainingTime)
        XCTAssertTrue(settings.remainingTimeRespectsSpeed)
    }
}
