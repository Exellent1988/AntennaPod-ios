import XCTest
@testable import AntennaPod

final class CarPlayBrowseModelTests: XCTestCase {
    func testDurationText() {
        XCTAssertNil(CarPlayBrowseModel.durationText(0))
        XCTAssertNil(CarPlayBrowseModel.durationText(.nan))
        XCTAssertEqual(CarPlayBrowseModel.durationText(65), "1:05")
        XCTAssertEqual(CarPlayBrowseModel.durationText(3725), "1:02:05")
    }

    func testNewerFirstPutsUndatedLast() {
        let dates: [Int64?] = [nil, 10, 30, 20]
        XCTAssertEqual(dates.sorted(by: CarPlayBrowseModel.newerFirst), [30, 20, 10, nil])
    }

    func testEmptyInputsGiveEmptyRows() {
        XCTAssertTrue(CarPlayBrowseModel.subscriptionRows([]).isEmpty)
        XCTAssertTrue(CarPlayBrowseModel.queueRows([]) { _ in nil }.isEmpty)
        XCTAssertTrue(CarPlayBrowseModel.downloadRows(feeds: []) { _ in true }.isEmpty)
    }
}

final class CarPlayLiveArtworkTests: XCTestCase {
    private func row(_ id: String, image: String? = nil) -> CarPlayRow {
        CarPlayRow(title: id, detail: nil, imageUrl: image, target: .episode(id))
    }

    func testArtworkURLPrefersFirstValidHTTP() {
        XCTAssertEqual(CarPlayBrowseModel.artworkURL(nil, "  ", "ftp://x/a.png", " https://x/b.jpg "), "https://x/b.jpg")
        XCTAssertEqual(CarPlayBrowseModel.artworkURL("http://ep.png", "https://feed.png"), "http://ep.png")
        XCTAssertNil(CarPlayBrowseModel.artworkURL(nil, "not a url"))
    }

    func testArtworkPixelSize() {
        XCTAssertEqual(CarPlayBrowseModel.artworkPixelSize(maxPoints: 44, scale: 3), 132)
        XCTAssertEqual(CarPlayBrowseModel.artworkPixelSize(maxPoints: 44, scale: 0), 44)
        XCTAssertEqual(CarPlayBrowseModel.artworkPixelSize(maxPoints: 0, scale: 2), 1)
    }

    func testUniqueArtworkURLsKeepsOrder() {
        let rows = [row("a", image: "u1"), row("b"), row("c", image: "u2"), row("d", image: "u1")]
        XCTAssertEqual(CarPlayBrowseModel.uniqueArtworkURLs(rows), ["u1", "u2"])
    }

    func testSnapshotIgnoresPlayingEpisodeNotInList() {
        let rows = [row("a"), row("b")]
        XCTAssertEqual(
            CarPlayListSnapshot(rows: rows, playingEpisodeId: "zzz"),
            CarPlayListSnapshot(rows: rows, playingEpisodeId: nil)
        )
    }

    func testSnapshotChangesWhenPlayingRowOrRowsChange() {
        let rows = [row("a"), row("b")]
        XCTAssertNotEqual(
            CarPlayListSnapshot(rows: rows, playingEpisodeId: "a"),
            CarPlayListSnapshot(rows: rows, playingEpisodeId: "b")
        )
        XCTAssertNotEqual(
            CarPlayListSnapshot(rows: rows, playingEpisodeId: nil),
            CarPlayListSnapshot(rows: [row("a")], playingEpisodeId: nil)
        )
    }
}
