import PodcastCore
import XCTest
@testable import AntennaPod

/// Skip intro / Skip ending: global default (AppSettings) vs per-podcast override (FeedSettings),
/// custom seconds beyond the presets, persistence, and the start / ending skip rules.
@MainActor
final class SkipIntroOutroResolutionTests: XCTestCase {
    func testFeedFallsBackToGlobal() {
        XCTAssertEqual(FeedSettings.default.resolvedSkipIntroSeconds(global: 30), 30)
        XCTAssertEqual(FeedSettings.default.resolvedSkipOutroSeconds(global: 15), 15)
        XCTAssertEqual(FeedSettings.default.resolvedSkipIntroSeconds(global: 0), 0)
    }

    func testFeedOverrideWinsIncludingOff() {
        let feed = FeedSettings(skipIntroSeconds: 45, skipOutroSeconds: 0)
        XCTAssertEqual(feed.resolvedSkipIntroSeconds(global: 10), 45)
        XCTAssertEqual(feed.resolvedSkipOutroSeconds(global: 60), 0, "Override 0 turns the ending skip off for this podcast")
    }

    func testCustomFeedSecondsAreKeptAndInvalidOnesFallBackToGlobal() throws {
        XCTAssertEqual(FeedSettings(skipIntroSeconds: 47).skipIntroSeconds, 47)
        XCTAssertNil(FeedSettings(skipIntroSeconds: -3).skipIntroSeconds)
        XCTAssertNil(FeedSettings(skipOutroSeconds: 99_999).skipOutroSeconds)
        let decoded = try JSONDecoder().decode(
            FeedSettings.self, from: JSONEncoder().encode(FeedSettings(skipIntroSeconds: 47, skipOutroSeconds: 120)))
        XCTAssertEqual(decoded.skipIntroSeconds, 47)
        XCTAssertEqual(decoded.skipOutroSeconds, 120)
    }

    func testGlobalCustomSecondsSurviveBackupAndUserDefaults() throws {
        let settings = AppSettings()
        let original = settings.backupSnapshot()
        defer { settings.applyBackupSnapshot(original) }
        settings.skipIntroSeconds = 47
        settings.skipOutroSeconds = 90
        XCTAssertEqual(AppSettings().skipIntroSeconds, 47, "UserDefaults keeps a custom value")
        XCTAssertEqual(AppSettings().skipOutroSeconds, 90)
        let snap = try JSONDecoder().decode(
            AppSettingsBackupSnapshot.self, from: JSONEncoder().encode(settings.backupSnapshot()))
        settings.skipIntroSeconds = 0
        settings.skipOutroSeconds = 0
        settings.applyBackupSnapshot(snap)
        XCTAssertEqual(settings.skipIntroSeconds, 47)
        XCTAssertEqual(settings.skipOutroSeconds, 90)
    }

    func testBackupWithOutOfRangeValueKeepsCurrent() throws {
        let settings = AppSettings()
        let original = settings.backupSnapshot()
        defer { settings.applyBackupSnapshot(original) }
        settings.skipIntroSeconds = 10
        var snap = settings.backupSnapshot()
        snap.skipIntroSeconds = -5
        settings.applyBackupSnapshot(snap)
        XCTAssertEqual(settings.skipIntroSeconds, 10)
    }

    func testStartAndEndingRulesUseResolvedValues() {
        let feed = FeedSettings(skipOutroSeconds: 60)
        let intro = Double(feed.resolvedSkipIntroSeconds(global: 30))
        let outro = Double(feed.resolvedSkipOutroSeconds(global: 0))
        XCTAssertTrue(SkipIntroOutro.introSeekFits(intro: intro, outro: outro, duration: 1800))
        XCTAssertFalse(SkipIntroOutro.introSeekFits(intro: intro, outro: outro, duration: 80))
        XCTAssertFalse(SkipIntroOutro.shouldSkipEnding(outro: outro, position: 1700, duration: 1800))
        XCTAssertTrue(SkipIntroOutro.shouldSkipEnding(outro: outro, position: 1745, duration: 1800))
    }
}
