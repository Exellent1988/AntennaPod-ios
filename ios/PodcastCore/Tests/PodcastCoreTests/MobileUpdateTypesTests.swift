import XCTest
@testable import PodcastCore

final class MobileUpdateTypesTests: XCTestCase {
    func testAndroidValuesAndDefault() {
        XCTAssertEqual(MobileUpdateType.allCases.map(\.rawValue),
                       ["feed_refresh", "episode_download", "auto_download", "streaming", "images"])
        XCTAssertEqual(MobileUpdateTypes.androidDefault, [.images])
    }

    func testMigrationKeepsPreviousIOSBehaviour() {
        XCTAssertEqual(MobileUpdateTypes.migrated(autoDownloadWifiOnly: nil, manualDownloadWifiOnly: nil, streamWifiOnly: nil),
                       [.feedRefresh, .images, .episodeDownload, .streaming], "iOS defaults")
        XCTAssertEqual(MobileUpdateTypes.migrated(autoDownloadWifiOnly: false, manualDownloadWifiOnly: true, streamWifiOnly: true),
                       [.feedRefresh, .images, .autoDownload])
    }

    func testEncodeDecode() {
        XCTAssertEqual(MobileUpdateTypes.encode([.images, .feedRefresh]), ["feed_refresh", "images"])
        XCTAssertEqual(MobileUpdateTypes.decode(["images", "future_type", "streaming"]), [.images, .streaming])
    }

    func testAllows() {
        XCTAssertTrue(MobileUpdateTypes.allows(.images, in: [], isOffline: false, isUnmetered: true))
        XCTAssertFalse(MobileUpdateTypes.allows(.images, in: [], isOffline: false, isUnmetered: false))
        XCTAssertTrue(MobileUpdateTypes.allows(.images, in: [.images], isOffline: false, isUnmetered: false))
        XCTAssertFalse(MobileUpdateTypes.allows(.images, in: [.images], isOffline: true, isUnmetered: false))
    }

    func testFeedRefreshDecision() {
        XCTAssertEqual(FeedRefreshNetworkDecision.decide(userInitiated: true, allowOnceOnMobile: false, allowed: true), .run)
        XCTAssertEqual(FeedRefreshNetworkDecision.decide(userInitiated: true, allowOnceOnMobile: false, allowed: false), .askUser)
        XCTAssertEqual(FeedRefreshNetworkDecision.decide(userInitiated: false, allowOnceOnMobile: false, allowed: false), .skip)
        XCTAssertEqual(FeedRefreshNetworkDecision.decide(userInitiated: true, allowOnceOnMobile: true, allowed: false), .run)
    }
}
