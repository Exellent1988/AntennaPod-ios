import PodcastCore
import XCTest

final class FavoriteKeepPolicyTests: XCTestCase {
    func testDefaultOnLikeAndroid() {
        XCTAssertTrue(FavoriteKeepPolicy.defaultFavoriteKeepsEpisode)
    }

    func testDeleteAfterPlaying() {
        XCTAssertFalse(FavoriteKeepPolicy.deleteAfterPlaying(autoDeleteAllowed: true, isFavorite: true, favoriteKeepsEpisode: true))
        XCTAssertTrue(FavoriteKeepPolicy.deleteAfterPlaying(autoDeleteAllowed: true, isFavorite: true, favoriteKeepsEpisode: false))
        XCTAssertTrue(FavoriteKeepPolicy.deleteAfterPlaying(autoDeleteAllowed: true, isFavorite: false, favoriteKeepsEpisode: true))
        XCTAssertFalse(FavoriteKeepPolicy.deleteAfterPlaying(autoDeleteAllowed: false, isFavorite: false, favoriteKeepsEpisode: false))
        XCTAssertFalse(FavoriteKeepPolicy.deleteAfterPlaying(autoDeleteAllowed: false, isFavorite: true, favoriteKeepsEpisode: false))
    }

    func testCleanupAlwaysKeepsFavorites() {
        XCTAssertFalse(FavoriteKeepPolicy.cleanupMayDelete(isFavorite: true))
        XCTAssertTrue(FavoriteKeepPolicy.cleanupMayDelete(isFavorite: false))
    }
}
