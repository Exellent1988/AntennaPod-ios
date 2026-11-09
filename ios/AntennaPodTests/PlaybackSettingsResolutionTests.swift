import AudioDSP
import PodcastCore
import XCTest
@testable import AntennaPod

/// Global default vs per-podcast override for the playback settings that exist in both places
/// (Android: UserPreferences + FeedPreferences). An unset override (`nil` / empty filter) must
/// fall through to the global value; a set override must win in both directions.
final class PlaybackSettingsResolutionTests: XCTestCase {

    // MARK: Playback speed

    func testSpeedFallsBackToGlobalWhenFeedHasNoOverride() {
        XCTAssertEqual(FeedSettings.default.resolvedPlaybackSpeed(global: 1.5), 1.5)
        XCTAssertEqual(FeedSettings.default.resolvedPlaybackSpeed(global: 1.0), 1.0)
    }

    func testFeedSpeedOverrideWinsOverGlobal() {
        let feed = FeedSettings(playbackSpeed: 2.0)
        XCTAssertEqual(feed.resolvedPlaybackSpeed(global: 1.0), 2.0)
        XCTAssertEqual(FeedSettings(playbackSpeed: 1.0).resolvedPlaybackSpeed(global: 1.5), 1.0,
                       "An explicit 1.0× override must beat a faster global default")
    }

    func testFeedSpeedOverrideSurvivesPersistence() throws {
        let decoded = try roundTrip(FeedSettings(playbackSpeed: 1.5))
        XCTAssertEqual(decoded.playbackSpeed, 1.5)
        XCTAssertNil(try roundTrip(.default).playbackSpeed)
    }

    // MARK: Volume adaptation

    func testVolumeAdaptationFallsBackToGlobal() {
        for global in VolumeAdaptationMode.allCases {
            XCTAssertEqual(FeedSettings.default.resolvedVolumeAdaptation(global: global), global)
        }
    }

    func testFeedVolumeAdaptationOverrideWins() {
        for feedMode in VolumeAdaptationMode.allCases {
            let feed = FeedSettings(volumeAdaptation: feedMode)
            for global in VolumeAdaptationMode.allCases {
                XCTAssertEqual(feed.resolvedVolumeAdaptation(global: global), feedMode)
            }
        }
    }

    func testFeedVolumeAdaptationOffOverridesGlobalBoost() {
        let feed = FeedSettings(volumeAdaptation: .off)
        XCTAssertEqual(feed.resolvedVolumeAdaptation(global: .heavyBoost), .off)
        XCTAssertNil(VolumeAdaptationMode.off.loudnessProfile)
    }

    func testVolumeAdaptationOverrideSurvivesPersistence() throws {
        XCTAssertEqual(try roundTrip(FeedSettings(volumeAdaptation: .heavyReduction)).volumeAdaptation, .heavyReduction)
        XCTAssertNil(try roundTrip(.default).volumeAdaptation)
    }

    // MARK: Skip silence (switch + level)

    func testSkipSilenceFollowsGlobalSwitchAndLevel() {
        let feed = FeedSettings.default
        XCTAssertEqual(feed.resolvedSkipSilenceLevel(globalEnabled: false, globalLevel: .aggressive), .off)
        XCTAssertEqual(feed.resolvedSkipSilenceLevel(globalEnabled: true, globalLevel: .mild), .mild)
        XCTAssertEqual(feed.resolvedSkipSilenceLevel(globalEnabled: true, globalLevel: .aggressive), .aggressive)
    }

    func testFeedSkipSilenceOnUsesGlobalLevelEvenWhenGlobalSwitchIsOff() {
        let feed = FeedSettings(skipSilence: true)
        XCTAssertEqual(feed.resolvedSkipSilenceLevel(globalEnabled: false, globalLevel: .aggressive), .aggressive)
        XCTAssertEqual(feed.resolvedSkipSilenceLevel(globalEnabled: false, globalLevel: .off), .medium,
                       "Forced on with no global level must still skip (medium)")
    }

    func testFeedSkipSilenceOffBeatsGlobalOn() {
        let feed = FeedSettings(skipSilence: false)
        XCTAssertEqual(feed.resolvedSkipSilenceLevel(globalEnabled: true, globalLevel: .aggressive), .off)
    }

    func testFeedSkipSilenceLevelBeatsEverything() {
        let feed = FeedSettings(skipSilence: false, skipSilenceLevel: .mild)
        XCTAssertEqual(feed.resolvedSkipSilenceLevel(globalEnabled: true, globalLevel: .aggressive), .mild)
        XCTAssertEqual(FeedSettings(skipSilenceLevel: .off)
            .resolvedSkipSilenceLevel(globalEnabled: true, globalLevel: .medium), .off)
    }

    func testSkipSilenceOverridesSurvivePersistence() throws {
        let decoded = try roundTrip(FeedSettings(skipSilence: true, skipSilenceLevel: .aggressive))
        XCTAssertEqual(decoded.skipSilence, true)
        XCTAssertEqual(decoded.skipSilenceLevel, .aggressive)
        XCTAssertNil(try roundTrip(.default).skipSilenceLevel)
    }

    // MARK: Episode filter (per-podcast only, like Android)

    func testNoFeedFilterAllowsEverything() {
        XCTAssertTrue(FeedSettings.default.allowsAutoDownloadEpisode(title: "Anything", durationSeconds: 5))
        XCTAssertTrue(FeedSettings.default.allowsAutoDownloadEpisode(title: "Trailer", durationSeconds: 0))
    }

    func testFeedFilterAppliesTermsAndDuration() {
        let feed = FeedSettings(episodeFilter: EpisodeFilter(
            includeTerms: "interview", excludeTerms: "trailer",
            minimumDurationSeconds: 600, maximumDurationSeconds: 7200))
        XCTAssertTrue(feed.allowsAutoDownloadEpisode(title: "Big Interview", durationSeconds: 1800))
        XCTAssertFalse(feed.allowsAutoDownloadEpisode(title: "Interview trailer", durationSeconds: 1800))
        XCTAssertFalse(feed.allowsAutoDownloadEpisode(title: "News", durationSeconds: 1800))
        XCTAssertFalse(feed.allowsAutoDownloadEpisode(title: "Interview", durationSeconds: 120))
        XCTAssertFalse(feed.allowsAutoDownloadEpisode(title: "Interview", durationSeconds: 9000))
        XCTAssertTrue(feed.allowsAutoDownloadEpisode(title: "Interview", durationSeconds: 0),
                      "Unknown duration must not be rejected by duration bounds")
    }

    func testFeedFilterSurvivesPersistence() throws {
        let filter = EpisodeFilter(includeTerms: "a, b", excludeTerms: "c", minimumDurationSeconds: 60)
        XCTAssertEqual(try roundTrip(FeedSettings(episodeFilter: filter)).episodeFilter, filter)
    }

    private func roundTrip(_ settings: FeedSettings) throws -> FeedSettings {
        try JSONDecoder().decode(FeedSettings.self, from: JSONEncoder().encode(settings))
    }
}
