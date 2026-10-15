import XCTest
import PodcastCore
@testable import GpodderLogic

/// In-memory gpodder server: stores uploaded actions with a server timestamp, returns those
/// newer than `since` (episode actions API: `GET ...?since=` → {actions, timestamp}).
final class FakeServer {
    private(set) var log: [(ts: Int64, action: GpodderEpisodeAction)] = []
    private(set) var clock: Int64 = 1000
    func upload(_ actions: [GpodderEpisodeAction]) -> Int64 { clock += 1; for a in actions { log.append((clock, a)) }; return clock }
    func pull(since: Int64) -> ([GpodderEpisodeAction], Int64) { (log.filter { $0.ts > since }.map(\.action), clock) }
}

/// One device. `sync` mirrors GpodderSyncService.syncEpisodeActions step by step (the method is
/// MainActor/store-bound and not Linux-buildable); every decision comes from the real
/// GpodderSyncLogic / GpodderActionQueue code.
final class Device {
    let id: String
    var refs: [GpodderSyncLogic.EpisodeRef]
    var states: [String: EpisodePlaybackState] = [:]
    var actionsTimestamp: Int64 = 0
    var uploadCursorMs: Int64 = 0
    let queue: GpodderActionQueue
    init(id: String, refs: [GpodderSyncLogic.EpisodeRef], queueFile: URL) {
        self.id = id; self.refs = refs; queue = GpodderActionQueue(fileURL: queueFile)
    }
    @discardableResult
    func sync(_ server: FakeServer, nowMs: Int64) -> (applied: Int, uploaded: Int) {
        let (remote, ts) = server.pull(since: actionsTimestamp)
        let updates = GpodderSyncLogic.remoteUpdates(actions: remote, refs: refs, localStates: states)
        let snapshot = GpodderSyncLogic.localActions(refs: refs, localStates: states, sinceMs: uploadCursorMs, deviceId: id)
        let queued = queue.snapshot
        let outgoing = GpodderSyncLogic.outgoingActions(queued: queued, snapshot: snapshot,
                                                        remotelyUpdatedIds: Set(updates.map(\.episodeId)))
        // GpodderSyncService order: upload first, then apply (skipping locally newer states).
        var timestamp = ts
        if !outgoing.isEmpty { timestamp = max(timestamp, server.upload(outgoing)); queue.remove(queued) }
        var applied = 0
        for u in updates where GpodderSyncLogic.isNewer(u, than: states[u.episodeId]) {
            states[u.episodeId] = GpodderSyncLogic.merged(u, onto: states[u.episodeId]
                ?? EpisodePlaybackState(positionSeconds: 0, durationSeconds: 0, isPlayed: false, updatedAtEpochMs: 0))
            applied += 1
        }
        actionsTimestamp = timestamp
        uploadCursorMs = nowMs
        return (applied, outgoing.count)
    }
    /// Reset app data: cursors and outbox cleared, playback states gone (GpodderSyncService.resetCursors).
    func resetAppData() { states = [:]; actionsTimestamp = 0; uploadCursorMs = 0; queue.clear() }
}

final class EpisodeActionRoundTripTests: XCTestCase {
    let feed = "https://pod.example/feed"
    var refs: [GpodderSyncLogic.EpisodeRef] {
        [.init(episodeId: "g1", feedUrl: feed, mediaUrl: "https://cdn.example/e1.mp3"),
         .init(episodeId: "g2", feedUrl: feed, mediaUrl: "https://cdn.example/e2.mp3")]
    }
    var dir: URL!
    override func setUp() { dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }
    func device(_ id: String) -> Device { Device(id: id, refs: refs, queueFile: dir.appendingPathComponent("\(id).json")) }
    // Whole seconds: gpodder timestamps have second resolution.
    let t0: Int64 = 1_760_000_000_000

    func testPositionAndPlayedSurviveBothDirections() {
        let server = FakeServer(), a = device("A"), b = device("B")
        a.states["g1"] = .init(positionSeconds: 600, durationSeconds: 3600, isPlayed: false, updatedAtEpochMs: t0, playStartedSeconds: 100)
        a.states["g2"] = .init(positionSeconds: 0, durationSeconds: 1800, isPlayed: true, updatedAtEpochMs: t0)
        XCTAssertEqual(a.sync(server, nowMs: t0 + 1000).uploaded, 2)
        let up = server.log.map(\.action).first { $0.guid == "g1" }!
        XCTAssertEqual([up.started, up.position, up.total], [100, 600, 3600])
        XCTAssertEqual(server.log.map(\.action).first { $0.guid == "g2" }?.position, 1800) // played → position = total

        XCTAssertEqual(b.sync(server, nowMs: t0 + 2000).applied, 2)
        XCTAssertEqual(b.states["g1"]?.positionSeconds, 600); XCTAssertEqual(b.states["g1"]?.isPlayed, false)
        XCTAssertEqual(b.states["g2"]?.isPlayed, true)
        XCTAssertEqual(server.log.count, 2, "B must not echo what it just applied")

        // Back direction: B continues g1, A picks it up.
        b.states["g1"]!.positionSeconds = 1200; b.states["g1"]!.playStartedSeconds = 600; b.states["g1"]!.updatedAtEpochMs = t0 + 10_000
        XCTAssertEqual(b.sync(server, nowMs: t0 + 11_000).uploaded, 1)
        XCTAssertEqual(a.sync(server, nowMs: t0 + 12_000).applied, 1)
        XCTAssertEqual(a.states["g1"]?.positionSeconds, 1200)
        XCTAssertEqual(server.log.count, 3)
    }

    func testRepeatedSyncAppliesNothingTwice() {
        let server = FakeServer(), a = device("A"), b = device("B")
        a.states["g1"] = .init(positionSeconds: 300, durationSeconds: 3600, isPlayed: false, updatedAtEpochMs: t0)
        a.sync(server, nowMs: t0 + 1000)
        XCTAssertEqual(b.sync(server, nowMs: t0 + 2000).applied, 1)
        XCTAssertEqual(b.sync(server, nowMs: t0 + 3000).applied, 0)
        XCTAssertEqual(a.sync(server, nowMs: t0 + 4000).applied, 0, "own upload pulled back is not newer")
        XCTAssertEqual(server.log.count, 1)
    }

    func testNewestTimestampWins() {
        let server = FakeServer(), a = device("A"), b = device("B")
        a.states["g1"] = .init(positionSeconds: 300, durationSeconds: 3600, isPlayed: false, updatedAtEpochMs: t0)
        b.states["g1"] = .init(positionSeconds: 900, durationSeconds: 3600, isPlayed: false, updatedAtEpochMs: t0 + 60_000)
        a.sync(server, nowMs: t0 + 1000)
        // B's local state is newer than A's action: kept, and B uploads it.
        let r = b.sync(server, nowMs: t0 + 61_000)
        XCTAssertEqual(r.applied, 0); XCTAssertEqual(r.uploaded, 1)
        XCTAssertEqual(b.states["g1"]?.positionSeconds, 900)
        a.sync(server, nowMs: t0 + 62_000)
        XCTAssertEqual(a.states["g1"]?.positionSeconds, 900)
        // Several remote actions for one episode in one pull: the newest one is applied.
        let fresh = device("C")
        XCTAssertEqual(fresh.sync(server, nowMs: t0 + 63_000).applied, 1)
        XCTAssertEqual(fresh.states["g1"]?.positionSeconds, 900)
    }

    func testOutboxPersistsDedupesAndSurvivesFailedUpload() throws {
        let file = dir.appendingPathComponent("q.json")
        func act(_ started: Int, _ pos: Int) -> GpodderEpisodeAction {
            .init(podcast: feed, episode: "https://cdn.example/e1.mp3", guid: "g1", action: "play",
                  timestamp: "2025-10-09T08:00:00", started: started, position: pos, total: 3600, device: "A")
        }
        var q: GpodderActionQueue? = GpodderActionQueue(fileURL: file)
        q!.enqueue(act(0, 100)); q!.enqueue(act(0, 200)) // same session → replaced
        q!.enqueue(act(200, 400))                         // new session
        XCTAssertEqual(q!.snapshot.map(\.position), [200, 400])
        q = nil // "app restart"
        let reloaded = GpodderActionQueue(fileURL: file)
        XCTAssertEqual(reloaded.snapshot.map(\.position), [200, 400])
        // Upload in flight; a new session is recorded meanwhile; only the uploaded ones go.
        let inFlight = reloaded.snapshot
        reloaded.enqueue(act(400, 500))
        reloaded.remove(inFlight)
        XCTAssertEqual(GpodderActionQueue(fileURL: file).snapshot.map(\.position), [500])
        // Queued action for an episode suppresses that episode's snapshot entry (no double upload).
        let snap = [act(0, 999)]
        XCTAssertEqual(GpodderSyncLogic.outgoingActions(queued: [act(400, 500)], snapshot: snap, remotelyUpdatedIds: []).count, 1)
    }

    func testQueuedSessionsAllReachServerAndFreshDeviceGetsLatest() {
        let server = FakeServer(), a = device("A"), b = device("B")
        for (i, (s, p)) in [(0, 300), (300, 900)].enumerated() {
            a.queue.enqueue(.init(podcast: feed, episode: "https://cdn.example/e1.mp3", guid: "g1", action: "play",
                                  timestamp: GpodderEpisodeAction.formatTimestamp(Date(timeIntervalSince1970: Double(t0 / 1000 + Int64(i) * 60))),
                                  started: s, position: p, total: 3600, device: "A"))
        }
        XCTAssertEqual(a.sync(server, nowMs: t0 + 200_000).uploaded, 2)
        XCTAssertTrue(a.queue.isEmpty)
        b.sync(server, nowMs: t0 + 201_000)
        XCTAssertEqual(b.states["g1"]?.positionSeconds, 900)
    }

    // MARK: Reset app data → full re-pull

    func testResetThenRepullReappliesIdempotently() {
        let server = FakeServer(), a = device("A")
        a.states["g1"] = .init(positionSeconds: 600, durationSeconds: 3600, isPlayed: false, updatedAtEpochMs: t0)
        a.states["g2"] = .init(positionSeconds: 0, durationSeconds: 1800, isPlayed: true, updatedAtEpochMs: t0)
        a.sync(server, nowMs: t0 + 1000)
        a.resetAppData()
        XCTAssertEqual(a.sync(server, nowMs: t0 + 5000).applied, 2)
        XCTAssertEqual(a.states["g1"]?.positionSeconds, 600)
        XCTAssertEqual(a.states["g2"]?.isPlayed, true)
        XCTAssertEqual(server.log.count, 2, "re-pull must not re-upload")
        a.actionsTimestamp = 0 // a second full pull applies nothing
        XCTAssertEqual(a.sync(server, nowMs: t0 + 6000).applied, 0)
    }

    func testRemoteMatchesMediaUrlSpellingVariant() {
        let server = FakeServer(), b = device("B")
        _ = server.upload([.init(podcast: "http://pod.example/feed/", episode: "http://CDN.example/e1.mp3", guid: nil,
                                 action: "play", timestamp: "2025-10-09T08:00:00", started: 0, position: 42, total: 3600, device: "X")])
        XCTAssertEqual(b.sync(server, nowMs: t0).applied, 1)
        XCTAssertEqual(b.states["g1"]?.positionSeconds, 42)
    }
}
