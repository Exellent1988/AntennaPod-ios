import PodcastCore
import XCTest

final class EnqueueLocationTests: XCTestCase {
    let q = ["a", "b", "c", "d"]

    func testDefaultIsBackAndUnknownFallsBack() {
        XCTAssertEqual(EnqueueLocation.defaultLocation, .back)
        XCTAssertEqual(EnqueueLocation(storedValue: nil), .back)
        XCTAssertEqual(EnqueueLocation(storedValue: "sideways"), .back)
        XCTAssertEqual(EnqueueLocation(storedValue: "afterCurrentlyPlaying"), .afterCurrentlyPlaying)
    }

    func testBackAppends() {
        XCTAssertEqual(EnqueuePosition.index(location: .back, queueIds: q, currentlyPlayingId: "b"), 4)
        XCTAssertEqual(EnqueuePosition.index(location: .back, queueIds: [], currentlyPlayingId: nil), 0)
    }

    func testFrontSkipsDownloadingItems() {
        XCTAssertEqual(EnqueuePosition.index(location: .front, queueIds: q, currentlyPlayingId: nil), 0)
        XCTAssertEqual(EnqueuePosition.index(location: .front, queueIds: q, currentlyPlayingId: nil,
                                             isDownloading: { ["a", "b"].contains($0) }), 2)
        XCTAssertEqual(EnqueuePosition.index(location: .front, queueIds: q, currentlyPlayingId: nil,
                                             isDownloading: { _ in true }), 4)
    }

    func testAfterCurrentlyPlaying() {
        XCTAssertEqual(EnqueuePosition.index(location: .afterCurrentlyPlaying, queueIds: q, currentlyPlayingId: "b"), 2)
        XCTAssertEqual(EnqueuePosition.index(location: .afterCurrentlyPlaying, queueIds: q, currentlyPlayingId: "d"), 4)
        // Playing item not queued (or nothing playing) → head, like Android (-1 + 1).
        XCTAssertEqual(EnqueuePosition.index(location: .afterCurrentlyPlaying, queueIds: q, currentlyPlayingId: "x"), 0)
        XCTAssertEqual(EnqueuePosition.index(location: .afterCurrentlyPlaying, queueIds: q, currentlyPlayingId: nil), 0)
        XCTAssertEqual(EnqueuePosition.index(location: .afterCurrentlyPlaying, queueIds: q, currentlyPlayingId: "a",
                                             isDownloading: { $0 == "b" }), 2)
    }

    func testRandomStaysInRangeIncludingEnd() {
        XCTAssertEqual(EnqueuePosition.index(location: .random, queueIds: q, currentlyPlayingId: nil, randomIndex: { $0.upperBound }), 4)
        XCTAssertEqual(EnqueuePosition.index(location: .random, queueIds: q, currentlyPlayingId: nil, randomIndex: { _ in 99 }), 4)
        for _ in 0..<50 {
            let i = EnqueuePosition.index(location: .random, queueIds: q, currentlyPlayingId: nil)
            XCTAssertTrue((0...4).contains(i))
        }
    }
}
