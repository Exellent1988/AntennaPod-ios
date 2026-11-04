import PodcastCore
import XCTest

final class EpisodeCleanupPolicyTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_000_000)
    func c(_ id: String, played: Bool = true, queued: Bool = false, fav: Bool = false,
           hoursAgo: Double? = 48, pubDay: Double? = nil) -> CleanupCandidate {
        CleanupCandidate(id: id, isPlayed: played, isQueued: queued, isFavorite: fav,
                         lastPlayedAt: hoursAgo.map { now.addingTimeInterval(-$0 * 3600) },
                         pubDate: pubDay.map { Date(timeIntervalSince1970: $0 * 86400) })
    }

    func testAndroidValuesAndDefault() {
        XCTAssertEqual(EpisodeCleanup.default, .never)
        XCTAssertEqual(EpisodeCleanup.options.map(\.androidValue), [-3, -1, 0, 12, 24, 72, 120, 168, -2])
        for o in EpisodeCleanup.options { XCTAssertEqual(EpisodeCleanup(androidValue: o.androidValue), o) }
        XCTAssertEqual(EpisodeCleanup(androidValue: -9), .never)
        XCTAssertEqual(EpisodeCleanupPolicy.defaultCacheSize, 20)
    }

    func testEligibility() {
        let fav = c("f", fav: true), queued = c("q", queued: true), unplayed = c("u", played: false), recent = c("r", hoursAgo: 1)
        let never = c("n", hoursAgo: nil)
        XCTAssertFalse(EpisodeCleanupPolicy.isEligible(c("x"), mode: .never, now: now))
        XCTAssertFalse(EpisodeCleanupPolicy.isEligible(fav, mode: .exceptFavorite, now: now))
        XCTAssertTrue(EpisodeCleanupPolicy.isEligible(queued, mode: .exceptFavorite, now: now))
        XCTAssertTrue(EpisodeCleanupPolicy.isEligible(unplayed, mode: .exceptFavorite, now: now))
        XCTAssertFalse(EpisodeCleanupPolicy.isEligible(queued, mode: .notInQueue, now: now))
        XCTAssertFalse(EpisodeCleanupPolicy.isEligible(fav, mode: .notInQueue, now: now))
        XCTAssertTrue(EpisodeCleanupPolicy.isEligible(unplayed, mode: .notInQueue, now: now))
        let h24 = EpisodeCleanup.afterFinishing(hours: 24)
        XCTAssertTrue(EpisodeCleanupPolicy.isEligible(c("x"), mode: h24, now: now))
        XCTAssertFalse(EpisodeCleanupPolicy.isEligible(recent, mode: h24, now: now))
        XCTAssertTrue(EpisodeCleanupPolicy.isEligible(recent, mode: .afterFinishing(hours: 0), now: now))
        XCTAssertFalse(EpisodeCleanupPolicy.isEligible(unplayed, mode: h24, now: now))
        XCTAssertFalse(EpisodeCleanupPolicy.isEligible(queued, mode: h24, now: now))
        XCTAssertFalse(EpisodeCleanupPolicy.isEligible(fav, mode: h24, now: now))
        XCTAssertFalse(EpisodeCleanupPolicy.isEligible(never, mode: h24, now: now))
    }

    func testVictimOrder() {
        let items = [c("a", hoursAgo: 30, pubDay: 3), c("b", hoursAgo: 90, pubDay: 1), c("c", hoursAgo: 60, pubDay: 2)]
        XCTAssertEqual(EpisodeCleanupPolicy.victims(items, mode: .afterFinishing(hours: 0), count: 2, now: now), ["b", "c"])
        XCTAssertEqual(EpisodeCleanupPolicy.victims(items, mode: .notInQueue, count: 5, now: now), ["b", "c", "a"])
        XCTAssertEqual(EpisodeCleanupPolicy.victims(items, mode: .never, count: 5, now: now), [])
        XCTAssertEqual(EpisodeCleanupPolicy.victims(items, mode: .exceptFavorite, count: 0, now: now), [])
    }

    func testNumbersLikeAndroid() {
        XCTAssertEqual(EpisodeCleanupPolicy.numberToCleanUp(downloaded: 20, roomNeeded: 3, cacheSize: 20), 3)
        XCTAssertEqual(EpisodeCleanupPolicy.numberToCleanUp(downloaded: 10, roomNeeded: 3, cacheSize: 20), 0)
        XCTAssertEqual(EpisodeCleanupPolicy.numberToCleanUp(downloaded: 25, roomNeeded: 0, cacheSize: 20), 5)
        XCTAssertEqual(EpisodeCleanupPolicy.numberToCleanUp(downloaded: 99, roomNeeded: 3, cacheSize: nil), 0)
        XCTAssertEqual(EpisodeCleanupPolicy.autoDownloadSpaceLeft(cacheSize: 20, downloaded: 20, deleted: 0, wanted: 3), 0)
        XCTAssertEqual(EpisodeCleanupPolicy.autoDownloadSpaceLeft(cacheSize: 20, downloaded: 20, deleted: 2, wanted: 3), 2)
        XCTAssertEqual(EpisodeCleanupPolicy.autoDownloadSpaceLeft(cacheSize: 20, downloaded: 5, deleted: 0, wanted: 3), 3)
        XCTAssertEqual(EpisodeCleanupPolicy.autoDownloadSpaceLeft(cacheSize: nil, downloaded: 500, deleted: 0, wanted: 3), 3)
        XCTAssertEqual(EpisodeCleanupPolicy.autoDownloadSpaceLeft(cacheSize: 5, downloaded: 9, deleted: 0, wanted: 3), 0)
    }

    func testMigrations() {
        XCTAssertEqual(EpisodeCleanupPolicy.migratedCacheSize(keyPresent: false, hasExistingData: false), .some(20))
        XCTAssertEqual(EpisodeCleanupPolicy.migratedCacheSize(keyPresent: false, hasExistingData: true), .some(nil))
        XCTAssertNil(EpisodeCleanupPolicy.migratedCacheSize(keyPresent: true, hasExistingData: false))
        XCTAssertEqual(EpisodeCleanupPolicy.migratedCleanup(keyPresent: false, existingCacheLimit: 50), .notInQueue)
        XCTAssertEqual(EpisodeCleanupPolicy.migratedCleanup(keyPresent: false, existingCacheLimit: nil), .never)
        XCTAssertNil(EpisodeCleanupPolicy.migratedCleanup(keyPresent: true, existingCacheLimit: 50))
    }

    func testStreamOverDownloadButton() {
        XCTAssertEqual(EpisodeRowPrimaryAction.forEpisode(isDownloaded: true, isDownloading: false, streamOverDownload: true), .play)
        XCTAssertEqual(EpisodeRowPrimaryAction.forEpisode(isDownloaded: false, isDownloading: true, streamOverDownload: true), .cancelDownload)
        XCTAssertEqual(EpisodeRowPrimaryAction.forEpisode(isDownloaded: false, isDownloading: false, streamOverDownload: true), .stream)
        XCTAssertEqual(EpisodeRowPrimaryAction.forEpisode(isDownloaded: false, isDownloading: false, streamOverDownload: false), .download)
    }
}
