import XCTest
@testable import PodcastCore

final class PlayerLayoutTests: XCTestCase {
    func testChapterMarks() {
        XCTAssertEqual(ChapterMarks.fractions(starts: [0, 300, 150, 600, 700], duration: 600), [0.25, 0.5])
        XCTAssertEqual(ChapterMarks.fractions(starts: [100, 101], duration: 1000), [0.1])
        XCTAssertEqual(ChapterMarks.fractions(starts: [10], duration: 0), [])
        XCTAssertEqual(ChapterMarks.fractions(starts: [.nan, 10], duration: 100), [0.1])
    }

    func testFeedSettingsOrderMatchesAndroid() {
        let first = Array(FeedSettingsRow.allCases.prefix(9))
        XCTAssertEqual(first, [.playbackSpeed, .volumeAdaptation, .skipSilence, .skipIntro, .skipOutro,
                               .autoDownload, .episodeFilter, .autoDelete, .keepUpdated])
        XCTAssertEqual(FeedSettingsGroup.ordered, [.playback, .downloads, .updates, .other])
        XCTAssertTrue(FeedSettingsRow.episodeFilter.dependsOnAutoDownload)
        XCTAssertFalse(FeedSettingsRow.autoDelete.dependsOnAutoDownload)
    }

    func testRowsAreContiguousPerGroup() {
        var closed: Set<FeedSettingsGroup> = []
        var current: FeedSettingsGroup?
        for row in FeedSettingsRow.allCases {
            if row.group != current {
                XCTAssertFalse(closed.contains(row.group), "\(row) splits its group")
                if let current { closed.insert(current) }
                current = row.group
            }
        }
    }
}
