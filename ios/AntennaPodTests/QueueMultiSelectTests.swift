import XCTest
@testable import AntennaPod

/// Android QueueFragment multi-select (episodes_apply_action_speeddial move_to_top_item / move_to_bottom_item):
/// moved episodes keep their relative queue order.
@MainActor
final class QueueMultiSelectTests: XCTestCase {
    private func ep(_ id: String) -> PodcastEpisode {
        PodcastEpisode(id: id, title: id, downloadUrl: "https://example.invalid/\(id).mp3", mimeType: "audio/mpeg", durationSeconds: 60)
    }

    func testMoveToTopAppliesBottomMostSelectedFirst() {
        let q = ["a", "b", "c", "d"].map(ep)
        let order = EpisodeMultiSelectModifier.queueMoveOrder(selection: ["d", "b"], queue: q, toTop: true)
        XCTAssertEqual(order.map(\.id), ["d", "b"])
    }

    func testMoveToBottomAppliesTopMostSelectedFirst() {
        let q = ["a", "b", "c", "d"].map(ep)
        let order = EpisodeMultiSelectModifier.queueMoveOrder(selection: ["c", "a"], queue: q, toTop: false)
        XCTAssertEqual(order.map(\.id), ["a", "c"])
    }

    func testIgnoresSelectedEpisodesNotInQueue() {
        let q = ["a", "b"].map(ep)
        XCTAssertEqual(EpisodeMultiSelectModifier.queueMoveOrder(selection: ["x", "b"], queue: q, toTop: true).map(\.id), ["b"])
    }
}
