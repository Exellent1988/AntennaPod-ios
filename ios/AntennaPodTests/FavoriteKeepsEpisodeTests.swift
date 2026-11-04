import PodcastCore
import XCTest
@testable import AntennaPod

/// Android `prefFavoriteKeepsEpisode` on the real store and settings.
@MainActor
final class FavoriteKeepsEpisodeTests: PlaybackFixtureTestCase {
    private var favorited: [String] = []

    override func tearDown() async throws {
        for id in favorited where store.isFavorite(id) { store.toggleFavorite(id) }
        try await super.tearDown()
    }

    private func favorite(_ ep: PodcastEpisode) {
        if !store.isFavorite(ep.id) { store.toggleFavorite(ep.id); favorited.append(ep.id) }
    }

    func testDefaultOnAndInBackup() {
        var probe = settings.backupSnapshot()
        probe.favoriteKeepsEpisode = nil
        settings.applyBackupSnapshot(probe)
        XCTAssertTrue(settings.favoriteKeepsEpisode, "Android default on")
        settings.favoriteKeepsEpisode = false
        XCTAssertEqual(settings.backupSnapshot().favoriteKeepsEpisode, false)
        XCTAssertFalse(AppSettings().favoriteKeepsEpisode, "persisted immediately")
        settings.applyBackupSnapshot(probe)
        XCTAssertTrue(settings.favoriteKeepsEpisode)
    }

    func testFavoriteKeptOnlyWhileSettingOn() {
        favorite(episodes[0])
        settings.favoriteKeepsEpisode = true
        XCTAssertTrue(store.favoriteKeepsEpisode(episodes[0].id))
        XCTAssertFalse(store.favoriteKeepsEpisode(episodes[1].id), "non-favorite is never kept by this rule")
        settings.favoriteKeepsEpisode = false
        XCTAssertFalse(store.favoriteKeepsEpisode(episodes[0].id))
    }
}
