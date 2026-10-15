import XCTest
@testable import PodcastCore

final class SessionPlaybackSpeedTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        suite = "SessionPlaybackSpeedTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testSavedSpeedForSameEpisodeWins() {
        let saved = SessionPlaybackSpeed(episodeId: "a", speed: 1.75)
        XCTAssertEqual(SessionPlaybackSpeed.resolve(episodeId: "a", saved: saved, feedOverride: 1.2, global: 1.0), 1.75)
    }

    func testSavedSpeedForOtherEpisodeIgnored() {
        let saved = SessionPlaybackSpeed(episodeId: "a", speed: 1.75)
        XCTAssertEqual(SessionPlaybackSpeed.resolve(episodeId: "b", saved: saved, feedOverride: 1.2, global: 1.0), 1.2)
        XCTAssertEqual(SessionPlaybackSpeed.resolve(episodeId: "b", saved: saved, feedOverride: nil, global: 1.5), 1.5)
    }

    func testInvalidSavedSpeedFallsBack() {
        let saved = SessionPlaybackSpeed(episodeId: "a", speed: 0)
        XCTAssertEqual(SessionPlaybackSpeed.resolve(episodeId: "a", saved: saved, feedOverride: nil, global: 1.3), 1.3)
    }

    func testSaveIsReadableByFreshDefaultsInstanceWithoutSynchronize() {
        SessionPlaybackSpeed(episodeId: "ep", speed: 2.25).save(to: defaults)
        let fresh = UserDefaults(suiteName: suite)!
        XCTAssertEqual(SessionPlaybackSpeed.load(from: fresh), SessionPlaybackSpeed(episodeId: "ep", speed: 2.25))
    }

    func testClearRemovesBothKeys() {
        SessionPlaybackSpeed(episodeId: "ep", speed: 2.0).save(to: defaults)
        SessionPlaybackSpeed.clear(in: defaults)
        XCTAssertNil(SessionPlaybackSpeed.load(from: defaults))
        XCTAssertNil(defaults.object(forKey: SessionPlaybackSpeed.speedKey))
    }

    func testKeysAreNotGlobalOrFeedKeys() {
        XCTAssertNotEqual(SessionPlaybackSpeed.speedKey, "settings.defaultPlaybackSpeed")
        XCTAssertTrue(SessionPlaybackSpeed.speedKey.hasPrefix("playback."))
    }
}
