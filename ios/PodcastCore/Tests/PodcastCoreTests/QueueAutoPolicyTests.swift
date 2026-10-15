import XCTest
@testable import PodcastCore

final class QueueAutoPolicyTests: XCTestCase {
    func testAndroidDefaults() {
        XCTAssertTrue(QueueAutoPolicy.defaultEnqueueDownloaded)
        XCTAssertFalse(QueueAutoPolicy.defaultDeleteRemovesFromQueue)
    }

    func testEnqueueOnDownloadRequest() {
        XCTAssertTrue(QueueAutoPolicy.enqueueOnDownloadRequest(enabled: true, alreadyQueued: false, alreadyDownloaded: false))
        XCTAssertFalse(QueueAutoPolicy.enqueueOnDownloadRequest(enabled: false, alreadyQueued: false, alreadyDownloaded: false))
        XCTAssertFalse(QueueAutoPolicy.enqueueOnDownloadRequest(enabled: true, alreadyQueued: true, alreadyDownloaded: false))
        XCTAssertFalse(QueueAutoPolicy.enqueueOnDownloadRequest(enabled: true, alreadyQueued: false, alreadyDownloaded: true))
    }

    func testRemoveOnCancelOnlyWhenDownloadAddedIt() {
        XCTAssertTrue(QueueAutoPolicy.removeOnCancel(wasQueuedByDownload: true, stillQueued: true))
        XCTAssertFalse(QueueAutoPolicy.removeOnCancel(wasQueuedByDownload: false, stillQueued: true))
        XCTAssertFalse(QueueAutoPolicy.removeOnCancel(wasQueuedByDownload: true, stillQueued: false))
    }

    func testRemoveOnDelete() {
        XCTAssertTrue(QueueAutoPolicy.removeOnDelete(enabled: true, isQueued: true))
        XCTAssertFalse(QueueAutoPolicy.removeOnDelete(enabled: false, isQueued: true))
        XCTAssertFalse(QueueAutoPolicy.removeOnDelete(enabled: true, isQueued: false))
    }
}
