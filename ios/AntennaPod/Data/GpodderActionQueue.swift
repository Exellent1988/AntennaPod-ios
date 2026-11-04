import Foundation

/// Persistent outbox of gpodder episode actions (Android `SynchronizationQueueStorage`).
///
/// Android enqueues one `play` action per pause / stop / end (`enqueueEpisodePlayed`) and
/// uploads the whole queue at the next sync, clearing it only after a successful upload, so
/// listening sessions survive offline periods, failed syncs and app restarts. The iOS
/// snapshot upload (`GpodderSyncLogic.localActions`) only knows each episode's latest state,
/// so it loses earlier sessions and anything whose episode / feed is gone before the sync.
///
/// - One entry per play session: an action with the same episode + `started` replaces the
///   older one (pause → end of the same session keeps only the final position).
/// - Persisted as JSON on every change (atomic write).
/// - Capped at `maxActions`; the oldest entries are dropped first.
/// - `remove(_:)` drops exactly the uploaded entries, so actions recorded during an upload stay.
final class GpodderActionQueue {
    static let maxActions = 1000
    static let shared = GpodderActionQueue(fileURL: GpodderActionQueue.defaultFileURL())

    let fileURL: URL
    private(set) var actions: [GpodderEpisodeAction] = []
    private let lock = NSLock()

    init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([GpodderEpisodeAction].self, from: data) {
            actions = Array(decoded.suffix(Self.maxActions))
        }
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("gpodder-action-queue.json")
    }

    var isEmpty: Bool { lock.withLock { actions.isEmpty } }
    var snapshot: [GpodderEpisodeAction] { lock.withLock { actions } }

    func enqueue(_ action: GpodderEpisodeAction) {
        lock.withLock {
            actions.removeAll { Self.sameSession($0, action) }
            actions.append(action)
            if actions.count > Self.maxActions {
                actions.removeFirst(actions.count - Self.maxActions)
            }
            saveLocked()
        }
    }

    /// Successful upload: drop the uploaded entries (one occurrence each).
    func remove(_ uploaded: [GpodderEpisodeAction]) {
        guard !uploaded.isEmpty else { return }
        lock.withLock {
            for item in uploaded {
                if let i = actions.firstIndex(of: item) { actions.remove(at: i) }
            }
            saveLocked()
        }
    }

    /// Login / logout / provider change (Android `clearQueue`).
    func clear() {
        lock.withLock {
            actions.removeAll()
            saveLocked()
        }
    }

    static func sameSession(_ a: GpodderEpisodeAction, _ b: GpodderEpisodeAction) -> Bool {
        a.action == b.action && a.episode == b.episode && a.started == b.started
    }

    private func saveLocked() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if actions.isEmpty {
                try? FileManager.default.removeItem(at: fileURL)
            } else {
                try JSONEncoder().encode(actions).write(to: fileURL, options: .atomic)
            }
        } catch {
            // Best effort: the snapshot upload still covers the latest state per episode.
        }
    }
}

extension GpodderSyncLogic {
    /// Upload batch: every queued session action, plus the state snapshot for episodes that
    /// have no queued action (mark played / unplayed and older app versions), minus snapshot
    /// entries the server just overrode.
    static func outgoingActions(
        queued: [GpodderEpisodeAction],
        snapshot: [GpodderEpisodeAction],
        remotelyUpdatedIds: Set<String>
    ) -> [GpodderEpisodeAction] {
        let queuedEpisodes = Set(queued.map(\.episode))
        let extra = snapshot.filter {
            !queuedEpisodes.contains($0.episode) && !remotelyUpdatedIds.contains($0.guid ?? "")
        }
        return queued + extra
    }
}
