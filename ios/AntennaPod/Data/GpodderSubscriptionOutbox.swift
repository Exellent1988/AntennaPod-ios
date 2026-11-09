import Foundation
import PodcastCore

/// Persistent queue of local unsubscribes for gpodder (Android `SynchronizationQueueStorage`
/// removed feeds). Survives restarts (JSON, atomic write on every change); entries are
/// dropped only after the server accepted the remove (`confirm`). Matching rules live in
/// PodcastCore `PendingSubscriptionRemovals`.
final class GpodderSubscriptionOutbox {
    static let shared = GpodderSubscriptionOutbox(fileURL: GpodderSubscriptionOutbox.defaultFileURL())

    let fileURL: URL
    private var pending: PendingSubscriptionRemovals
    private let lock = NSLock()

    init(fileURL: URL) {
        self.fileURL = fileURL
        pending = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode(PendingSubscriptionRemovals.self, from: $0) } ?? .init()
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("gpodder-subscription-outbox.json")
    }

    var snapshot: PendingSubscriptionRemovals { lock.withLock { pending } }

    /// Local unsubscribe (all URLs of the podcast).
    func record(_ urls: [String]) { mutate { $0.record(urls) } }
    /// Local subscribe: cancels a pending remove of the same podcast.
    func cancel(_ urls: [String]) { mutate { $0.cancel(urls) } }
    /// Pull: drop adds of pending podcasts, remember the server's spellings.
    func absorbingPull(_ add: [String]) -> [String] {
        var out: [String] = []
        mutate { out = $0.absorbingPull(add) }
        return out
    }
    /// Push accepted: drop the entries that were sent.
    func confirm(_ sent: PendingSubscriptionRemovals) { mutate { $0.confirm(sent) } }
    /// Login / logout / reset.
    func clear() { mutate { $0 = .init() } }

    private func mutate(_ change: (inout PendingSubscriptionRemovals) -> Void) {
        lock.withLock {
            let before = pending
            change(&pending)
            guard pending != before else { return }
            do {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if pending.isEmpty {
                    try? FileManager.default.removeItem(at: fileURL)
                } else {
                    try JSONEncoder().encode(pending).write(to: fileURL, options: .atomic)
                }
            } catch {
                // Best effort; the in-memory queue still uploads this session.
            }
        }
    }
}
