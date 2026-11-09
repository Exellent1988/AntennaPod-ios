import XCTest
@testable import PodcastCore

/// Android PodDBAdapter.getFeedCounters semantics per FeedCounter mode.
final class FeedCounterTests: XCTestCase {
    private let inbox = FeedCounterEpisode(isPlayed: false, isArchived: false, isDownloaded: false)
    private let archivedUnplayed = FeedCounterEpisode(isPlayed: false, isArchived: true, isDownloaded: false)
    private let played = FeedCounterEpisode(isPlayed: true, isArchived: false, isDownloaded: false)
    private let downloadedUnplayed = FeedCounterEpisode(isPlayed: false, isArchived: true, isDownloaded: true)
    private let downloadedPlayed = FeedCounterEpisode(isPlayed: true, isArchived: false, isDownloaded: true)

    private var all: [FeedCounterEpisode] { [inbox, archivedUnplayed, played, downloadedUnplayed, downloadedPlayed] }

    func testNoneIsAlwaysZero() {
        XCTAssertEqual(FeedCounterRule.count(.none, episodes: all, isLocalFolderFeed: true), 0)
    }

    func testNewCountsOnlyInboxEpisodes() {
        XCTAssertEqual(FeedCounterRule.count(.new, episodes: all, isLocalFolderFeed: false), 1)
    }

    func testUnplayedIncludesArchivedButNotPlayed() {
        XCTAssertEqual(FeedCounterRule.count(.unplayed, episodes: all, isLocalFolderFeed: false), 3)
    }

    func testDownloadedCountsDownloadsOrEveryLocalFolderEpisode() {
        XCTAssertEqual(FeedCounterRule.count(.downloaded, episodes: all, isLocalFolderFeed: false), 2)
        XCTAssertEqual(FeedCounterRule.count(.downloaded, episodes: all, isLocalFolderFeed: true), 5)
    }

    func testDownloadedUnplayedNeedsBoth() {
        XCTAssertEqual(FeedCounterRule.count(.downloadedUnplayed, episodes: all, isLocalFolderFeed: false), 1)
        XCTAssertEqual(FeedCounterRule.count(.downloadedUnplayed, episodes: all, isLocalFolderFeed: true), 3)
    }

    func testRawValuesAreStable() {
        XCTAssertEqual(FeedCounterKind.allCases.map(\.rawValue), ["none", "new", "unplayed", "downloaded", "downloadedUnplayed"])
    }
}
