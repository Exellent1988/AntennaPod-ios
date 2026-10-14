import XCTest
@testable import AntennaPod

final class NowPlayingLogicTests: XCTestCase {
    func testChapterAtPosition() {
        let ch: [(start: Double, title: String)] = [(60, "B"), (0, "A"), (120, "C")]
        XCTAssertEqual(NowPlayingLogic.chapter(at: 0, starts: ch), .init(index: 0, count: 3, title: "A"))
        XCTAssertEqual(NowPlayingLogic.chapter(at: 90, starts: ch)?.title, "B")
        XCTAssertEqual(NowPlayingLogic.chapter(at: 500, starts: ch)?.index, 2)
        XCTAssertNil(NowPlayingLogic.chapter(at: 5, starts: [(10, "Late")]))
        XCTAssertNil(NowPlayingLogic.chapter(at: 5, starts: []))
    }

    func testArtistLine() {
        XCTAssertEqual(NowPlayingLogic.artistLine(feedName: "Pod", chapterTitle: nil), "Pod")
        XCTAssertEqual(NowPlayingLogic.artistLine(feedName: "Pod", chapterTitle: "  "), "Pod")
        XCTAssertEqual(NowPlayingLogic.artistLine(feedName: "Pod", chapterTitle: "Intro"), "Intro")
    }

    func testSupportedAndNearestRates() {
        let r = NowPlayingLogic.supportedRates(presets: [1.0, 1.5, 0.8], current: 1.25)
        XCTAssertEqual(r, [0.8, 1.0, 1.25, 1.5])
        XCTAssertEqual(NowPlayingLogic.supportedRates(presets: [1.0, 1.5], current: 1.0004), [1.0, 1.5])
        XCTAssertEqual(NowPlayingLogic.nearestRate(1.4, supported: r), 1.5)
        XCTAssertNil(NowPlayingLogic.nearestRate(1, supported: []))
    }

    func testSkipIntervals() {
        XCTAssertTrue(NowPlayingLogic.skipIntervals(rewind: 15, forward: 45) == (15, 45))
        XCTAssertTrue(NowPlayingLogic.skipIntervals(rewind: 0, forward: .nan) == (10, 30))
    }

    func testAspectFitLandscapeIsCenteredNotStretched() {
        let r = NowPlayingLogic.aspectFitRect(imageWidth: 200, imageHeight: 100, side: 100)
        XCTAssertEqual(r, .init(x: 0, y: 25, width: 100, height: 50))
    }

    func testAspectFitWithPaddingAndSquare() {
        XCTAssertEqual(NowPlayingLogic.aspectFitRect(imageWidth: 50, imageHeight: 50, side: 100),
                       .init(x: 0, y: 0, width: 100, height: 100))
        let r = NowPlayingLogic.aspectFitRect(imageWidth: 100, imageHeight: 200, side: 100, padding: 10)
        XCTAssertEqual(r, .init(x: 30, y: 10, width: 40, height: 80))
        XCTAssertEqual(NowPlayingLogic.aspectFitRect(imageWidth: 0, imageHeight: 10, side: 100).width, 100)
    }

    func testPadding() {
        XCTAssertEqual(NowPlayingLogic.padding(imageWidth: 300, imageHeight: 300, side: 132), 0)
        XCTAssertEqual(NowPlayingLogic.padding(imageWidth: 400, imageHeight: 300, side: 132), 5)
    }

    func testCacheFileNameStableAndDistinct() {
        let a = NowPlayingLogic.cacheFileName(url: "https://x/a.jpg", pixels: 132)
        XCTAssertEqual(a, NowPlayingLogic.cacheFileName(url: "https://x/a.jpg", pixels: 132))
        XCTAssertNotEqual(a, NowPlayingLogic.cacheFileName(url: "https://x/a.jpg", pixels: 600))
        XCTAssertNotEqual(a, NowPlayingLogic.cacheFileName(url: "https://x/b.jpg", pixels: 132))
        XCTAssertTrue(a.hasSuffix(".png"))
        XCTAssertEqual(a.count, 20)
    }

    func testUpNext() {
        XCTAssertEqual(CarPlayParity.upNext(queueIds: ["a", "b", "c"], currentId: "b"), ["c"])
        XCTAssertEqual(CarPlayParity.upNext(queueIds: ["a", "b"], currentId: "z"), ["a", "b"])
        XCTAssertEqual(CarPlayParity.upNext(queueIds: ["a"], currentId: "a"), [])
    }
}

final class ArtworkDiskCacheLRUTests: XCTestCase {
    private func e(_ n: String, _ b: Int64, _ t: TimeInterval) -> NowPlayingLogic.CacheEntry {
        .init(name: n, bytes: b, modified: Date(timeIntervalSince1970: t))
    }

    func testUnderLimitEvictsNothing() {
        XCTAssertEqual(NowPlayingLogic.evictions([e("a", 10, 1), e("b", 10, 2)], limit: 20), [])
    }

    func testEvictsOldestUntilUnderLimit() {
        let entries = [e("new", 40, 30), e("old", 40, 10), e("mid", 40, 20)]
        XCTAssertEqual(NowPlayingLogic.evictions(entries, limit: 80), ["old"])
        XCTAssertEqual(NowPlayingLogic.evictions(entries, limit: 50), ["old", "mid"])
        XCTAssertEqual(NowPlayingLogic.evictions(entries, limit: 0), ["old", "mid", "new"])
    }

    func testTieBreaksByName() {
        XCTAssertEqual(NowPlayingLogic.evictions([e("b", 10, 1), e("a", 10, 1)], limit: 10), ["a"])
    }

    func testDefaultLimitIs50MB() {
        XCTAssertEqual(NowPlayingLogic.diskCacheLimitBytes, 52_428_800)
    }
}

final class AndroidAutoSkipParityTests: XCTestCase {
    func testNextTrackMatchesAndroidCarMode() {
        XCTAssertEqual(NowPlayingLogic.nextTrackAction(inCar: true), .skipEpisode)
        XCTAssertEqual(NowPlayingLogic.nextTrackAction(inCar: false), .hardwareButton)
        XCTAssertEqual(NowPlayingLogic.previousTrackAction(), .hardwareButton)
    }

    func testNextChapterStart() {
        let starts: [Double] = [120, 0, 60]
        XCTAssertEqual(NowPlayingLogic.nextChapterStart(starts: starts, at: 10), 60)
        XCTAssertEqual(NowPlayingLogic.nextChapterStart(starts: starts, at: 60), 120)
        XCTAssertNil(NowPlayingLogic.nextChapterStart(starts: starts, at: 130))
        XCTAssertNil(NowPlayingLogic.nextChapterStart(starts: [], at: 0))
        XCTAssertEqual(NowPlayingLogic.nextChapterStart(starts: [30, 90], at: 5), 30)
    }

    func testSleepToggleMinutes() {
        XCTAssertEqual(NowPlayingLogic.sleepToggleMinutes(presets: [5, 10, 15, 30]), 15)
        XCTAssertEqual(NowPlayingLogic.sleepToggleMinutes(presets: [20, 40]), 20)
        XCTAssertEqual(NowPlayingLogic.sleepToggleMinutes(presets: []), 15)
    }

    func testNowPlayingButtonsOrderAndLimit() {
        XCTAssertEqual(NowPlayingLogic.nowPlayingButtons(hasChapters: true), [.rate, .sleepTimer, .nextChapter, .skipEpisode])
        XCTAssertEqual(NowPlayingLogic.nowPlayingButtons(hasChapters: false), [.rate, .sleepTimer, .skipEpisode])
        XCTAssertLessThanOrEqual(NowPlayingLogic.nowPlayingButtons(hasChapters: true).count, 5)
    }
}
