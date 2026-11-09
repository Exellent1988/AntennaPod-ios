import XCTest
@testable import AntennaPod

/// Persistent gpodder outbox (Android SynchronizationQueueStorage + SyncService upload).
@MainActor
final class GpodderActionQueueTests: XCTestCase {
    private var dir: URL!
    private var fileURL: URL { dir.appendingPathComponent("queue.json") }

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("gq-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func play(_ ep: String, started: Int, position: Int, total: Int = 100) -> GpodderEpisodeAction {
        GpodderEpisodeAction(podcast: "https://e/feed", episode: "https://e/\(ep).mp3", guid: ep, action: "play",
                             timestamp: "2026-10-15T04:00:00", started: started, position: position,
                             total: total, device: "ios_test")
    }

    func testPersistsAcrossRestart() {
        let q = GpodderActionQueue(fileURL: fileURL)
        q.enqueue(play("a", started: 0, position: 10))
        q.enqueue(play("b", started: 5, position: 20))
        let reloaded = GpodderActionQueue(fileURL: fileURL)
        XCTAssertEqual(reloaded.snapshot, q.snapshot)
        XCTAssertEqual(reloaded.snapshot.count, 2)
    }

    func testOneActionPerSessionLatestWins() {
        let q = GpodderActionQueue(fileURL: fileURL)
        q.enqueue(play("a", started: 0, position: 10))
        q.enqueue(play("a", started: 0, position: 30))     // same session (pause → end)
        q.enqueue(play("a", started: 30, position: 45))    // resumed: new session
        XCTAssertEqual(q.snapshot.map(\.position), [30, 45])
        XCTAssertEqual(q.snapshot.map(\.started), [0, 30])
    }

    func testCapDropsOldest() {
        let q = GpodderActionQueue(fileURL: fileURL)
        for i in 0..<(GpodderActionQueue.maxActions + 5) {
            q.enqueue(play("e\(i)", started: 0, position: 1))
        }
        XCTAssertEqual(q.snapshot.count, GpodderActionQueue.maxActions)
        XCTAssertEqual(q.snapshot.first?.guid, "e5")
        XCTAssertEqual(GpodderActionQueue(fileURL: fileURL).snapshot.count, GpodderActionQueue.maxActions)
    }

    func testRemoveUploadedKeepsActionsRecordedDuringUpload() {
        let q = GpodderActionQueue(fileURL: fileURL)
        q.enqueue(play("a", started: 0, position: 10))
        let uploading = q.snapshot
        q.enqueue(play("b", started: 0, position: 7))      // recorded while the POST was in flight
        q.remove(uploading)
        XCTAssertEqual(q.snapshot.map(\.guid), ["b"])
        XCTAssertEqual(GpodderActionQueue(fileURL: fileURL).snapshot.map(\.guid), ["b"])
    }

    func testFailedUploadKeepsQueueAndClearRemovesFile() {
        let q = GpodderActionQueue(fileURL: fileURL)
        q.enqueue(play("a", started: 0, position: 10))
        // Upload threw → remove(_:) is never called; queue survives a restart.
        XCTAssertEqual(GpodderActionQueue(fileURL: fileURL).snapshot.count, 1)
        q.clear()
        XCTAssertTrue(q.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testCorruptFileStartsEmpty() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fileURL)
        XCTAssertTrue(GpodderActionQueue(fileURL: fileURL).isEmpty)
    }

    func testOutgoingMergesQueueWithSnapshotForOtherEpisodes() {
        let queued = [play("a", started: 0, position: 10), play("a", started: 10, position: 20)]
        let snapshot = [play("a", started: 10, position: 20), play("b", started: 0, position: 5),
                        play("c", started: 0, position: 9)]
        let out = GpodderSyncLogic.outgoingActions(queued: queued, snapshot: snapshot, remotelyUpdatedIds: ["c"])
        XCTAssertEqual(out.map(\.guid), ["a", "a", "b"], "every queued session, snapshot only for b; c overridden by server")
    }

    func testStoreRecordsOnlyWhenLoggedInAndForSubscribedHttpEpisodes() {
        let store = PodcastStore()
        let savedFeeds = store.feeds, savedStates = store.playbackStates
        defer { store.feeds = savedFeeds; store.playbackStates = savedStates }
        let queue = GpodderActionQueue(fileURL: fileURL)
        store.gpodderActionQueue = queue
        var loggedIn = false
        store.isGpodderActionRecordingEnabled = { loggedIn }

        let id = "gq-\(UUID().uuidString)"
        let episode = PodcastEpisode(id: id, title: "Q", downloadUrl: "https://example.com/\(id).mp3",
                                     mimeType: "audio/mpeg", durationSeconds: 100)
        store.feeds.append(PodcastFeed(
            id: UUID(), title: "Q feed", feedUrl: "https://example.com/feed-\(id).xml", siteLink: nil, imageUrl: nil,
            descriptionText: "", author: nil, language: nil, fundingUrl: nil, fundingLabel: nil, categories: [],
            isLocked: false, lockedOwner: nil, podcastGuid: nil, episodes: [episode]))
        store.notePlayStarted(id, atSeconds: 12)

        store.recordGpodderPlayAction(id, positionSeconds: 40, durationSeconds: 100)
        XCTAssertTrue(queue.isEmpty, "Android: nothing queued without a connected provider")

        loggedIn = true
        store.recordGpodderPlayAction(id, positionSeconds: 40, durationSeconds: 100)
        store.recordGpodderPlayAction(id, positionSeconds: 55, durationSeconds: 100)   // same session
        store.recordGpodderPlayAction("not-subscribed", positionSeconds: 40, durationSeconds: 100)
        let a = queue.snapshot
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a.first?.started, 12)
        XCTAssertEqual(a.first?.position, 55)
        XCTAssertEqual(a.first?.total, 100)
        XCTAssertEqual(a.first?.episode, "https://example.com/\(id).mp3")

        store.notePlayStarted(id, atSeconds: 55)
        store.recordGpodderPlayAction(id, positionSeconds: 55, durationSeconds: 100)   // no progress
        XCTAssertEqual(queue.snapshot.count, 1, "no action for a no-progress session")
    }
}
