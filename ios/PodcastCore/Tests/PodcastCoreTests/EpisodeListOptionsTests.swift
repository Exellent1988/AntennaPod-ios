import XCTest
@testable import PodcastCore

final class EpisodeListOptionsTests: XCTestCase {
    private let items: [EpisodeListFacts] = [
        .init(isPlayed: true, isDownloaded: true, pubDateEpochMs: 3, durationSeconds: 100, title: "b", feedTitle: "Y", sizeBytes: 300),
        .init(positionSeconds: 10, isQueued: true, isFavorite: true, hasChapters: true, pubDateEpochMs: 1, durationSeconds: 0, title: "a", feedTitle: "X", sizeBytes: 100),
        .init(hasMedia: false, pubDateEpochMs: nil, durationSeconds: 50, title: "C", feedTitle: "Z", sizeBytes: 0),
    ]

    func testPairsAreExclusiveAndAnd() {
        var f = EpisodeListFilter()
        f.toggle(.played); f.toggle(.unplayed)
        XCTAssertEqual(f.tokens, [.unplayed])
        f.toggle(.paused)
        XCTAssertEqual(items.filter(f.matches).map(\.title), ["a"])
        f.toggle(.paused)
        XCTAssertTrue(f.tokens == [.unplayed])
        f.toggle(.noMedia)
        XCTAssertEqual(items.filter(f.matches).map(\.title), ["C"])
    }

    func testEachToken() {
        func t(_ x: EpisodeFilterToken) -> [String] { items.filter(EpisodeListFilter([x]).matches).map(\.title) }
        XCTAssertEqual(t(.downloaded), ["b"]); XCTAssertEqual(t(.notDownloaded), ["a", "C"])
        XCTAssertEqual(t(.queued), ["a"]); XCTAssertEqual(t(.favorite), ["a"]); XCTAssertEqual(t(.notFavorite), ["b", "C"])
        XCTAssertEqual(t(.hasChapters), ["a"]); XCTAssertEqual(t(.notPaused), ["b", "C"])
    }

    func testSortUnknownLastBothWays() {
        func s(_ o: EpisodeListSortOrder) -> [String] { o.sorted(items) { $0 }.map(\.title) }
        XCTAssertEqual(s(.dateNewOld), ["b", "a", "C"]); XCTAssertEqual(s(.dateOldNew), ["a", "b", "C"])
        XCTAssertEqual(s(.durationShortLong), ["C", "b", "a"]); XCTAssertEqual(s(.durationLongShort), ["b", "C", "a"])
        XCTAssertEqual(s(.sizeSmallLarge), ["a", "b", "C"]); XCTAssertEqual(s(.sizeLargeSmall), ["b", "a", "C"])
        XCTAssertEqual(s(.titleAZ), ["a", "b", "C"]); XCTAssertEqual(s(.feedTitleZA), ["C", "b", "a"])
    }

    func testOptionsApplyAndCodable() {
        let o = EpisodeListOptions(filter: .init([.notPaused]), sort: .titleZA)
        XCTAssertEqual(o.apply(items) { $0 }.map(\.title), ["C", "b"])
        XCTAssertEqual(EpisodeListOptions.decode(o.encoded()), o)
        XCTAssertEqual(EpisodeListOptions.decode(nil), EpisodeListOptions())
    }
}
