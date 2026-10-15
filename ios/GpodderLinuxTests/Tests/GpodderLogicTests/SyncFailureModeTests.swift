import XCTest
import PodcastCore
@testable import GpodderLogic

struct InjectedFailure: Error {}

/// Server whose next download/upload can fail (5xx / timeout / 401 all surface as a thrown
/// error before the response is used; the app's GpodderClient throws for each).
final class FlakyServer {
    var actions: [(ts: Int64, a: GpodderEpisodeAction)] = []
    var subs: [(ts: Int64, add: [String], remove: [String])] = []
    var clock: Int64 = 100
    var failNextDownload = false, failNextUpload = false
    /// true = request reached the server and was stored, but the reply was lost (timeout).
    var uploadStoredBeforeFailure = false
    func pullActions(since: Int64) throws -> ([GpodderEpisodeAction], Int64) {
        if failNextDownload { failNextDownload = false; throw InjectedFailure() }
        return (actions.filter { $0.ts > since }.map(\.a), clock)
    }
    func uploadActions(_ list: [GpodderEpisodeAction]) throws -> Int64 {
        if failNextUpload {
            failNextUpload = false
            if uploadStoredBeforeFailure { clock += 1; list.forEach { actions.append((clock, $0)) } }
            throw InjectedFailure()
        }
        clock += 1; list.forEach { actions.append((clock, $0)) }; return clock
    }
    /// Current server subscription set (gpodder semantics: add/remove are idempotent per URL).
    var subscriptionURLs: [String] {
        var cur: [String] = []
        for c in subs { cur.removeAll { c.remove.contains($0) }; for u in c.add where !cur.contains(u) { cur.append(u) } }
        return cur
    }
    func pullSubs(since: Int64) throws -> SubscriptionDelta {
        if failNextDownload { failNextDownload = false; throw InjectedFailure() }
        if since == 0 { return SubscriptionDelta(add: subscriptionURLs, remove: [], timestamp: clock) }
        let later = subs.filter { $0.ts > since }
        return SubscriptionDelta(add: later.flatMap(\.add), remove: later.flatMap(\.remove), timestamp: clock)
    }
    func pushSubs(add: [String]) throws -> PushResult {
        if failNextUpload {
            failNextUpload = false
            if uploadStoredBeforeFailure { clock += 1; subs.append((clock, add, [])) }
            throw InjectedFailure()
        }
        clock += 1; subs.append((clock, add, [])); return PushResult(timestamp: clock, updateUrls: nil)
    }
}

/// One device; each round mirrors GpodderSyncService.syncNow / syncEpisodeActions in order
/// (pull → subscribe missing → unsubscribe removed → push → commit cursor; actions: pull →
/// compute → apply → upload → remove queued → advance cursors). A throw leaves the rest undone,
/// exactly like `try` in the app. Decisions come from real PodcastCore / GpodderSyncLogic code.
final class SyncDevice {
    var library: [[String]] = []
    var subCursor = SubscriptionSyncCursor()
    var refs: [GpodderSyncLogic.EpisodeRef]
    var states: [String: EpisodePlaybackState] = [:]
    var actionsTimestamp: Int64 = 0, uploadCursorMs: Int64 = 0
    let queue: GpodderActionQueue
    init(refs: [GpodderSyncLogic.EpisodeRef], queueFile: URL) { self.refs = refs; queue = GpodderActionQueue(fileURL: queueFile) }

    func syncSubscriptions(_ s: FlakyServer) throws {
        let delta = try s.pullSubs(since: subCursor.since)
        var remote = subCursor.applyingPull(delta)
        for u in SubscriptionSyncPlan.urlsToImport(remote: delta.add, localFeedURLs: library.flatMap { $0 }) { library.append([u]) }
        if subCursor.since > 0 {
            let drop = Set(SubscriptionSyncPlan.podcastsToUnsubscribe(remove: delta.remove, add: delta.add, localPodcasts: library))
            library = library.enumerated().filter { !drop.contains($0.offset) }.map(\.element)
        }
        let up = SubscriptionSyncPlan.urlsToUpload(localPodcasts: library, remoteKeys: remote)
        var push: PushResult?
        if !up.isEmpty { let r = try s.pushSubs(add: up); remote = SubscriptionSyncCursor.applyingPush(remote, uploaded: up, result: r); push = r }
        subCursor = .committed(pull: delta, keys: remote, push: push)
    }

    @discardableResult
    func syncActions(_ s: FlakyServer, nowMs: Int64) throws -> Int {
        let (remote, ts) = try s.pullActions(since: actionsTimestamp)
        let updates = GpodderSyncLogic.remoteUpdates(actions: remote, refs: refs, localStates: states)
        let snapshot = GpodderSyncLogic.localActions(refs: refs, localStates: states, sinceMs: uploadCursorMs, deviceId: "D")
        let queued = queue.snapshot
        let outgoing = GpodderSyncLogic.outgoingActions(queued: queued, snapshot: snapshot, remotelyUpdatedIds: Set(updates.map(\.episodeId)))
        for u in updates {
            var st = states[u.episodeId] ?? .init(positionSeconds: 0, durationSeconds: 0, isPlayed: false, updatedAtEpochMs: 0)
            st.isPlayed = st.isPlayed || u.isPlayed
            if !u.isPlayed { st.positionSeconds = u.positionSeconds }
            if u.durationSeconds > 0 { st.durationSeconds = u.durationSeconds }
            st.updatedAtEpochMs = u.updatedAtEpochMs
            states[u.episodeId] = st
        }
        var timestamp = ts
        if !outgoing.isEmpty { timestamp = max(timestamp, try s.uploadActions(outgoing)); queue.remove(queued) }
        actionsTimestamp = timestamp
        uploadCursorMs = nowMs
        return outgoing.count
    }
}

final class SyncFailureModeTests: XCTestCase {
    let feed = "https://pod.example/feed"
    var dir: URL!
    override func setUp() { dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }
    var refs: [GpodderSyncLogic.EpisodeRef] {
        [.init(episodeId: "g1", feedUrl: feed, mediaUrl: "https://cdn.example/e1.mp3"),
         .init(episodeId: "g2", feedUrl: feed, mediaUrl: "https://cdn.example/e2.mp3")]
    }
    func device(_ n: String = "d") -> SyncDevice { SyncDevice(refs: refs, queueFile: dir.appendingPathComponent("\(n).json")) }
    let t0: Int64 = 1_760_000_000_000
    func play(_ started: Int, _ pos: Int, sec: Int64 = 0) -> GpodderEpisodeAction {
        .init(podcast: feed, episode: "https://cdn.example/e1.mp3", guid: "g1", action: "play",
              timestamp: GpodderEpisodeAction.formatTimestamp(Date(timeIntervalSince1970: Double(t0 / 1000 + sec))),
              started: started, position: pos, total: 3600, device: "D")
    }

    // MARK: 1+2 episode actions

    func testActionsDownloadFailureKeepsOutboxAndCursors() throws {
        let s = FlakyServer(), d = device()
        d.queue.enqueue(play(0, 300)); d.actionsTimestamp = 7; d.uploadCursorMs = 5
        s.failNextDownload = true
        XCTAssertThrowsError(try d.syncActions(s, nowMs: t0))
        XCTAssertEqual(d.queue.snapshot.count, 1)
        XCTAssertEqual([d.actionsTimestamp, d.uploadCursorMs], [7, 5])
        XCTAssertEqual(try d.syncActions(s, nowMs: t0 + 1000), 1)
        XCTAssertTrue(d.queue.isEmpty); XCTAssertEqual(s.actions.count, 1)
    }

    func testActionsUploadFailureKeepsOutboxCursorsAndRetryUploadsOnce() throws {
        let s = FlakyServer(), d = device()
        d.queue.enqueue(play(0, 300))
        d.states["g2"] = .init(positionSeconds: 100, durationSeconds: 1800, isPlayed: false, updatedAtEpochMs: t0)
        s.failNextUpload = true
        XCTAssertThrowsError(try d.syncActions(s, nowMs: t0 + 1000))
        XCTAssertEqual(d.queue.snapshot, [play(0, 300)], "outbox kept")
        XCTAssertEqual([d.actionsTimestamp, d.uploadCursorMs], [0, 0], "cursors not advanced")
        XCTAssertEqual(try d.syncActions(s, nowMs: t0 + 2000), 2)
        XCTAssertEqual(s.actions.count, 2, "exactly one copy each after the retry")
        XCTAssertEqual(try d.syncActions(s, nowMs: t0 + 3000), 0)
    }

    func testActionsUploadStoredButReplyLostRetryResendsSameActionsHarmlessly() throws {
        // Timeout after the server stored the batch: the client cannot know, so it resends.
        // Same action twice on the server; other devices apply it once (not newer than itself).
        let s = FlakyServer(), d = device("a"), other = device("b")
        d.queue.enqueue(play(0, 300))
        s.failNextUpload = true; s.uploadStoredBeforeFailure = true
        XCTAssertThrowsError(try d.syncActions(s, nowMs: t0 + 1000))
        s.uploadStoredBeforeFailure = false
        try d.syncActions(s, nowMs: t0 + 2000)
        XCTAssertEqual(s.actions.count, 2)
        XCTAssertEqual(s.actions[0].a, s.actions[1].a)
        try other.syncActions(s, nowMs: t0 + 3000)
        XCTAssertEqual(other.states["g1"]?.positionSeconds, 300)
        XCTAssertEqual(try other.syncActions(s, nowMs: t0 + 4000), 0)
    }

    func testUploadFailureAfterApplyingRemoteEchoesRemoteStateOnceOnRetry() throws {
        let s = FlakyServer(), a = device("a"), b = device("b")
        a.queue.enqueue(play(0, 900, sec: 10))
        try a.syncActions(s, nowMs: t0 + 20_000)
        b.queue.enqueue(play(0, 60, sec: 0).with(episode: "https://cdn.example/e2.mp3", guid: "g2"))
        b.uploadCursorMs = t0 - 1 // B synced before; A's action (t0+10s) is newer than B's cursor
        s.failNextUpload = true
        XCTAssertThrowsError(try b.syncActions(s, nowMs: t0 + 30_000))
        XCTAssertEqual(b.states["g1"]?.positionSeconds, 900, "remote applied before the failed upload")
        try b.syncActions(s, nowMs: t0 + 40_000)
        let g1Copies = s.actions.filter { $0.a.guid == "g1" }.count
        // KNOWN, NOT FIXED (app-only, GpodderSyncService.syncEpisodeActions): remote updates are
        // applied before the upload; when the upload fails the upload cursor stays, so the retry
        // snapshot re-sends A's position as B's action once. Harmless (same position and
        // timestamp; no device applies it again, checked below) but a duplicate on the server.
        XCTAssertEqual(g1Copies, 2)
        try a.syncActions(s, nowMs: t0 + 50_000)
        XCTAssertEqual(a.states["g1"]?.positionSeconds, 900, "echo carries the same position; nothing changes for A")
    }

    // MARK: 1+2 subscriptions

    func testSubscriptionPushFailureKeepsLocalAndCursorThenUploadsOnce() throws {
        let s = FlakyServer(), d = device()
        try d.syncSubscriptions(s)
        let before = d.subCursor
        d.library.append(["https://new.example/rss"])
        s.failNextUpload = true
        XCTAssertThrowsError(try d.syncSubscriptions(s))
        XCTAssertEqual(d.subCursor, before)
        XCTAssertEqual(d.library, [["https://new.example/rss"]])
        try d.syncSubscriptions(s)
        try d.syncSubscriptions(s)
        XCTAssertEqual(s.subs.count, 1)
        XCTAssertEqual(s.subscriptionURLs, ["https://new.example/rss"])
    }

    func testSubscriptionPullFailureChangesNothing() throws {
        let s = FlakyServer(), d = device()
        s.subs = [(150, ["https://a.example/f"], [])]; s.clock = 150
        d.library = [["https://mine.example/f"]]
        s.failNextDownload = true
        XCTAssertThrowsError(try d.syncSubscriptions(s))
        XCTAssertEqual(d.library, [["https://mine.example/f"]]); XCTAssertEqual(d.subCursor, .reset)
        try d.syncSubscriptions(s)
        XCTAssertEqual(Set(d.library.flatMap { $0 }), ["https://mine.example/f", "https://a.example/f"])
        XCTAssertEqual(Set(s.subscriptionURLs), ["https://mine.example/f", "https://a.example/f"])
    }

    func testPushStoredButReplyLostRetryDoesNotDuplicate() throws {
        let s = FlakyServer(), d = device()
        try d.syncSubscriptions(s)
        d.library.append(["http://new.example/rss/"])
        s.failNextUpload = true; s.uploadStoredBeforeFailure = true
        XCTAssertThrowsError(try d.syncSubscriptions(s))
        s.uploadStoredBeforeFailure = false
        try d.syncSubscriptions(s) // re-pull sees its own add → known → not uploaded again
        XCTAssertEqual(s.subs.count, 1)
        XCTAssertEqual(d.library.count, 1)
    }

    // MARK: 3 401: same thrown path, nothing wiped / marked synced (error text is app-side)

    func testAuthFailureMidRoundWipesNothing() throws {
        let s = FlakyServer(), d = device()
        s.subs = [(150, ["https://a.example/f"], [])]; s.clock = 150
        try d.syncSubscriptions(s)
        d.queue.enqueue(play(0, 300))
        let lib = d.library, cur = d.subCursor
        s.failNextDownload = true // 401 on pull
        XCTAssertThrowsError(try d.syncSubscriptions(s))
        s.failNextDownload = true
        XCTAssertThrowsError(try d.syncActions(s, nowMs: t0))
        XCTAssertEqual(d.library, lib); XCTAssertEqual(d.subCursor, cur)
        XCTAssertEqual(d.queue.snapshot.count, 1); XCTAssertEqual(d.actionsTimestamp, 0)
    }

    // MARK: 4 variants on re-pull

    func testVariantsOnServerCountOnceOnRepull() throws {
        let s = FlakyServer(), d = device()
        s.subs = [(150, ["https://a.example/feed", "http://a.example/feed/", "https://A.example//feed"], [])]; s.clock = 150
        d.library = [["https://new.example/rss", "http://old.example/rss"]]
        s.subs.append((151, ["http://old.example/rss/"], [])); s.clock = 151
        try d.syncSubscriptions(s)
        XCTAssertEqual(d.library.count, 2)
        XCTAssertEqual(SubscriptionSyncPlan.distinctRemoteCount(s.subscriptionURLs), 2)
        d.subCursor = .reset
        try d.syncSubscriptions(s)
        XCTAssertEqual(d.library.count, 2)
    }
}

extension GpodderEpisodeAction {
    func with(episode: String, guid: String) -> GpodderEpisodeAction { var c = self; c.episode = episode; c.guid = guid; return c }
}
