import XCTest
@testable import AntennaPod

/// Android FeedItemMenuHandler reset_position (feeditem_options.xml): visible when position != 0;
/// sets position 0 and marks the episode unplayed.
@MainActor
final class EpisodeResetPositionTests: XCTestCase {
    func testResetPositionClearsPositionAndPlayed() {
        let store = PodcastStore()
        let saved = store.playbackStates
        defer { store.playbackStates = saved }
        var state = store.playbackState(for: "rp1")
        state.positionSeconds = 42
        state.isPlayed = true
        store.playbackStates["rp1"] = state
        XCTAssertTrue(store.canResetPosition("rp1"))

        store.resetPosition("rp1")

        XCTAssertEqual(store.playbackStates["rp1"]?.positionSeconds, 0)
        XCTAssertFalse(store.isPlayed("rp1"))
        XCTAssertFalse(store.canResetPosition("rp1"), "hidden once position is 0")
    }

    func testHiddenWithoutPosition() {
        let store = PodcastStore()
        XCTAssertFalse(store.canResetPosition("rp-none-\(UUID().uuidString)"))
    }
}
