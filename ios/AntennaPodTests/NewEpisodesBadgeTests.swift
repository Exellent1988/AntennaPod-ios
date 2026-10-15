import XCTest
@testable import AntennaPod

/// Inbox "new" badge: Android NavListAdapter shows the Inbox count (getNumberOfNewItems) and InboxFragment
/// remove_all_inbox_item clears it (DBWriter.removeAllNewFlags after remove_all_inbox_confirmation_msg).
/// iOS adds a switch to hide the always-visible tab badge.
@MainActor
final class NewEpisodesBadgeTests: XCTestCase {
    func testBadgeValueFollowsSetting() {
        XCTAssertEqual(AppSettings.newEpisodesBadgeValue(inboxCount: 7, enabled: true), 7)
        XCTAssertEqual(AppSettings.newEpisodesBadgeValue(inboxCount: 7, enabled: false), 0, "0 hides the SwiftUI badge")
        XCTAssertEqual(AppSettings.newEpisodesBadgeValue(inboxCount: 0, enabled: true), 0)
    }

    func testDefaultOnAndBackupRoundTrip() throws {
        let settings = AppSettings()
        let saved = settings.showNewEpisodesBadge
        defer { settings.showNewEpisodesBadge = saved }
        settings.showNewEpisodesBadge = false
        let snap = try JSONDecoder().decode(AppSettingsBackupSnapshot.self,
                                            from: JSONEncoder().encode(settings.backupSnapshot()))
        XCTAssertEqual(snap.showNewEpisodesBadge, false)
        settings.showNewEpisodesBadge = true
        settings.applyBackupSnapshot(snap)
        XCTAssertFalse(settings.showNewEpisodesBadge)
        var old = snap
        old.showNewEpisodesBadge = nil
        settings.applyBackupSnapshot(old)
        XCTAssertFalse(settings.showNewEpisodesBadge, "older backups leave the switch unchanged")
    }

    func testRemoveAllFromInboxEmptiesTheBadgeSource() {
        let store = PodcastStore()
        let saved = (store.feeds, store.archivedAtById, store.playbackStates)
        defer { store.feeds = saved.0; store.archivedAtById = saved.1; store.playbackStates = saved.2 }
        let feed = PodcastFeed(
            id: UUID(), title: "f", feedUrl: "https://nb.example/feed", siteLink: nil, imageUrl: nil,
            descriptionText: nil, author: nil, language: nil, fundingUrl: nil, fundingLabel: nil, categories: [],
            isLocked: false, lockedOwner: nil, podcastGuid: nil,
            episodes: ["nb1", "nb2", "nb3"].map { PodcastEpisode(id: $0, title: $0, downloadUrl: "https://e/\($0).mp3",
                                                                 mimeType: "audio/mpeg", durationSeconds: 60) })
        store.feeds = [feed]
        store.archivedAtById = [:]
        XCTAssertEqual(store.inboxEpisodes.count, 3)

        store.archiveAllInbox()

        XCTAssertEqual(store.inboxEpisodes.count, 0)
        XCTAssertEqual(AppSettings.newEpisodesBadgeValue(inboxCount: store.inboxEpisodes.count, enabled: true), 0)
        XCTAssertFalse(store.isPlayed("nb1"), "remove from inbox does not mark played (Android removeNewFlag)")
    }
}
