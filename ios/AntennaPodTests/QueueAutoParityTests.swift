import PodcastCore
import XCTest
@testable import AntennaPod

/// Android prefEnqueueDownloaded / prefDeleteRemovesFromQueue on the real DownloadService.
/// Uses the app's DownloadService (one background URLSession per identifier), pointed at the
/// fixture store/settings for the test and restored afterwards. Downloads target an unroutable
/// host and are cancelled at once, so nothing is fetched.
@MainActor
final class QueueAutoParityTests: PlaybackFixtureTestCase {
    private var downloads: DownloadService!
    private var savedStore: PodcastStore?
    private var savedSettings: AppSettings?

    override func setUp() async throws {
        try await super.setUp()
        downloads = try XCTUnwrap(AppServices.downloads, "test host app creates the DownloadService")
        savedStore = downloads.store
        savedSettings = downloads.settings
        downloads.store = store
        downloads.settings = settings
        store.downloads = downloads
        settings.manualDownloadWifiOnly = false
        store.queue = []
    }

    override func tearDown() async throws {
        for ep in remoteEpisodes { downloads.cancelDownload(ep) }
        downloads.store = savedStore
        downloads.settings = savedSettings
        try await super.tearDown()
    }

    private lazy var remoteEpisodes: [PodcastEpisode] = (1...3).map {
        PodcastEpisode(id: "qa-\(UUID().uuidString.prefix(6))-\($0)", title: "QA \($0)",
                       downloadUrl: "https://qa-parity.invalid/ep\($0).mp3", mimeType: "audio/mpeg", durationSeconds: 60)
    }

    func testDefaultsMatchAndroid() {
        var probe = settings.backupSnapshot()
        probe.enqueueDownloaded = nil; probe.deleteRemovesFromQueue = nil
        settings.applyBackupSnapshot(probe)
        XCTAssertTrue(settings.enqueueDownloaded, "Android default on")
        XCTAssertFalse(settings.deleteRemovesFromQueue, "Android default off")
    }

    func testBackupRoundTrip() {
        settings.enqueueDownloaded = false
        settings.deleteRemovesFromQueue = true
        let snap = settings.backupSnapshot()
        settings.enqueueDownloaded = true
        settings.deleteRemovesFromQueue = false
        settings.applyBackupSnapshot(snap)
        XCTAssertFalse(settings.enqueueDownloaded)
        XCTAssertTrue(settings.deleteRemovesFromQueue)
        XCTAssertFalse(AppSettings().enqueueDownloaded, "persisted immediately")
    }

    func testDownloadRequestEnqueuesAtEnqueueLocation() {
        settings.enqueueDownloaded = true
        settings.enqueueLocation = .front
        store.queue = [episodes[0], episodes[1]]
        requestDownload(remoteEpisodes[0])
        XCTAssertEqual(store.queue.first?.id, remoteEpisodes[0].id, "Front location")
        XCTAssertEqual(store.queue.count, 3)
    }

    func testFrontKeepsOrderForSeveralDownloads() {
        settings.enqueueDownloaded = true
        settings.enqueueLocation = .front
        store.queue = [episodes[0]]
        for ep in remoteEpisodes { requestDownload(ep) }
        XCTAssertEqual(store.queue.map(\.id), remoteEpisodes.map(\.id) + [episodes[0].id],
                       "skips items still downloading, like Android ItemEnqueuePositionCalculator")
    }

    func testDisabledDoesNotEnqueue() {
        settings.enqueueDownloaded = false
        requestDownload(remoteEpisodes[0])
        XCTAssertFalse(store.isInQueue(remoteEpisodes[0].id))
    }

    func testCancelRemovesOnlyWhatTheDownloadAdded() {
        settings.enqueueDownloaded = true
        store.queue = [remoteEpisodes[1]]
        requestDownload(remoteEpisodes[0])
        requestDownload(remoteEpisodes[1])
        downloads.cancelDownload(remoteEpisodes[0])
        downloads.cancelDownload(remoteEpisodes[1])
        XCTAssertFalse(store.isInQueue(remoteEpisodes[0].id), "added by the download → removed on cancel")
        XCTAssertTrue(store.isInQueue(remoteEpisodes[1].id), "was queued before → stays")
    }

    func testDeleteRemovesFromQueueWhenOn() {
        settings.deleteRemovesFromQueue = true
        store.queue = [episodes[0], episodes[1]]
        downloads.delete(episodes[0])
        XCTAssertEqual(store.queue.map(\.id), [episodes[1].id])
    }

    func testDeleteKeepsQueueWhenOff() {
        settings.deleteRemovesFromQueue = false
        store.queue = [episodes[0]]
        downloads.delete(episodes[0])
        XCTAssertTrue(store.isInQueue(episodes[0].id))
    }

    /// Drives `DownloadService.download` from a synchronous test. Async test methods in this
    /// class aborted the test host in swift_task_dealloc_specific (XCTSwiftErrorObservation,
    /// no app frames) on iOS 26.5, so the async call runs in its own Task.
    private func requestDownload(_ episode: PodcastEpisode) {
        let done = expectation(description: "download requested")
        let service = downloads!
        Task { @MainActor in
            await service.download(episode)
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
    }

}
