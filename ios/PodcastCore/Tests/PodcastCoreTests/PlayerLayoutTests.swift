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

final class PlayerHeroLayoutTests: XCTestCase {
    func testPortraitPhonesFitControlsBelowCover() {
        // iPhone SE (375×~603 content), 17 (402×~760), Pro Max (440×~850)
        for (w, h) in [(375.0, 603.0), (402.0, 760.0), (440.0, 850.0)] {
            let side = PlayerHeroLayout.coverSide(width: w, height: h)
            XCTAssertLessThanOrEqual(side, w - 48)
            XCTAssertLessThanOrEqual(side + PlayerHeroLayout.portraitControlsHeight, h + 0.001)
            XCTAssertGreaterThanOrEqual(side, PlayerHeroLayout.minimumCover)
        }
        XCTAssertEqual(PlayerHeroLayout.coverSide(width: 402, height: 760), 354)
    }

    func testLandscapeUsesHeightAndLeavesRoomForControls() {
        let side = PlayerHeroLayout.coverSide(width: 874, height: 360)
        XCTAssertEqual(side, 328)
        XCTAssertTrue(PlayerHeroLayout.isLandscape(width: 874, height: 360))
    }

    func testClamps() {
        XCTAssertEqual(PlayerHeroLayout.coverSide(width: 2000, height: 3000), PlayerHeroLayout.maximumCover)
        XCTAssertEqual(PlayerHeroLayout.coverSide(width: 100, height: 200), PlayerHeroLayout.minimumCover)
        XCTAssertEqual(PlayerHeroLayout.coverSide(width: 0, height: 0), PlayerHeroLayout.minimumCover)
    }
}

final class SeekBarGeometryTests: XCTestCase {
    func testThumbIsSmallAndRound() {
        XCTAssertLessThanOrEqual(SeekBarGeometry.thumbDiameter, 16)
        XCTAssertGreaterThanOrEqual(SeekBarGeometry.hitHeight, 44)
    }

    func testEndsSitAtThumbCentres() {
        XCTAssertEqual(SeekBarGeometry.x(forFraction: 0, width: 300), 7)
        XCTAssertEqual(SeekBarGeometry.x(forFraction: 1, width: 300), 293)
    }

    func testChapterTickAndThumbShareCoordinates() {
        for f in [0.0, 0.1, 0.37, 0.5, 0.99, 1.0] {
            let x = SeekBarGeometry.x(forFraction: f, width: 327)
            XCTAssertEqual(SeekBarGeometry.fraction(forX: x, width: 327), f, accuracy: 1e-9)
        }
    }

    func testClampsOutsideAndNonFinite() {
        XCTAssertEqual(SeekBarGeometry.fraction(forX: -50, width: 300), 0)
        XCTAssertEqual(SeekBarGeometry.fraction(forX: 900, width: 300), 1)
        XCTAssertEqual(SeekBarGeometry.clampedFraction(.nan), 0)
        XCTAssertEqual(SeekBarGeometry.fraction(forX: 10, width: 5), 0)
    }

    func testBottomBarInsetKeepsRowOffTheEdge() {
        XCTAssertGreaterThanOrEqual(PlayerHeroLayout.bottomBarInset, 12)
    }
}
