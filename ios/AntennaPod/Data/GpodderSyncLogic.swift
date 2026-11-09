import Foundation
import PodcastCore

/// Pure gpodder merge helpers (no I/O, no MainActor) so import dedupe and
/// episode-action mapping can be unit tested without a server or PodcastStore.
enum GpodderSyncLogic {
    /// Remote URLs to subscribe (PodcastCore `SubscriptionSyncPlan`: http(s) only, not local
    /// under any alias, one per Android-equality key, first spelling and remote order kept).
    static func urlsToImport(remote: [String], localFeedURLs: [String]) -> [String] {
        SubscriptionSyncPlan.urlsToImport(remote: remote, localFeedURLs: localFeedURLs)
    }

    /// Runs `operation` for every item with at most `maxConcurrent` in flight.
    /// Returns per-item errors (item, message) in input order; `progress(done)` after each item.
    static func runBounded(
        _ items: [String],
        maxConcurrent: Int,
        operation: @escaping @Sendable (String) async throws -> Void,
        progress: @escaping @Sendable (Int) async -> Void = { _ in }
    ) async -> [(String, String)] {
        let limit = max(1, maxConcurrent)
        var errors: [Int: (String, String)] = [:]
        var done = 0
        await withTaskGroup(of: (Int, String?).self) { group in
            var next = 0
            func addNext() {
                guard next < items.count else { return }
                let index = next
                let item = items[index]
                next += 1
                group.addTask {
                    do {
                        try await operation(item)
                        return (index, nil)
                    } catch {
                        return (index, error.localizedDescription)
                    }
                }
            }
            for _ in 0..<min(limit, items.count) { addNext() }
            while let (index, message) = await group.next() {
                if let message { errors[index] = (items[index], message) }
                done += 1
                await progress(done)
                addNext()
            }
        }
        return errors.keys.sorted().compactMap { errors[$0] }
    }

    /// Local episode identity for matching gpodder actions (`podcast` feed URL + `episode` media URL, or guid).
    struct EpisodeRef: Equatable {
        var episodeId: String
        var feedUrl: String
        var mediaUrl: String?
    }

    struct RemoteUpdate: Equatable {
        var episodeId: String
        var positionSeconds: Double
        var durationSeconds: Double
        var isPlayed: Bool
        var updatedAtEpochMs: Int64
    }

    /// Latest remote `play` action per local episode, applied only when newer than the local state.
    /// Played = `position >= total - 5s` with a known total (AntennaPod Android convention).
    static func remoteUpdates(
        actions: [GpodderEpisodeAction],
        refs: [EpisodeRef],
        localStates: [String: EpisodePlaybackState]
    ) -> [RemoteUpdate] {
        var byMedia: [String: String] = [:]
        var byGuid: [String: String] = [:]
        for ref in refs {
            if let m = ref.mediaUrl, !m.isEmpty { byMedia[GpodderSyncService.normalizeFeedURL(m)] = ref.episodeId }
            byGuid[ref.episodeId] = ref.episodeId
        }
        var latest: [String: (GpodderEpisodeAction, Int64)] = [:]
        for action in actions where action.action.lowercased() == "play" {
            guard action.position != nil, let date = action.date else { continue }
            let id = byMedia[GpodderSyncService.normalizeFeedURL(action.episode)]
                ?? action.guid.flatMap { byGuid[$0] }
            guard let id else { continue }
            let ms = Int64(date.timeIntervalSince1970 * 1000)
            if let existing = latest[id], existing.1 >= ms { continue }
            latest[id] = (action, ms)
        }
        var updates: [RemoteUpdate] = []
        for (id, entry) in latest {
            let (action, ms) = entry
            if let local = localStates[id], local.updatedAtEpochMs >= ms { continue }
            let total = Double(max(0, action.total ?? 0))
            let position = Double(max(0, action.position ?? 0))
            let played = total > 0 && position >= total - 5
            updates.append(RemoteUpdate(
                episodeId: id,
                positionSeconds: played ? 0 : position,
                durationSeconds: total,
                isPlayed: played,
                updatedAtEpochMs: ms
            ))
        }
        return updates.sorted { $0.episodeId < $1.episodeId }
    }

    /// Local playback changes since `sinceMs` as gpodder `play` actions.
    /// Skips episodes without an http(s) media URL or without a known duration
    /// (gpodder requires started/position/total for `play`).
    static func localActions(
        refs: [EpisodeRef],
        localStates: [String: EpisodePlaybackState],
        sinceMs: Int64,
        deviceId: String
    ) -> [GpodderEpisodeAction] {
        var result: [GpodderEpisodeAction] = []
        for ref in refs {
            guard let state = localStates[ref.episodeId], state.updatedAtEpochMs > sinceMs else { continue }
            guard let media = ref.mediaUrl, media.lowercased().hasPrefix("http") else { continue }
            guard ref.feedUrl.lowercased().hasPrefix("http") else { continue }
            let total = Int(state.durationSeconds.rounded())
            guard total > 0 else { continue }
            guard state.isPlayed || state.positionSeconds > 1 else { continue }
            // Android SynchronizationQueueImpl.enqueueEpisodePlayed: position = total when completed,
            // else the real position (also for a skip before the smart-mark window); started = the
            // session start; no action when an incomplete session made no progress.
            let completed = state.isPlayed && state.playActionPositionSeconds == nil
            let rawPosition = completed ? Double(total)
                : (state.isPlayed ? state.playActionPositionSeconds ?? 0 : state.positionSeconds)
            let position = min(total, max(0, Int(rawPosition.rounded())))
            let started = min(position, max(0, Int((state.playStartedSeconds ?? 0).rounded())))
            if !completed, state.playStartedSeconds != nil, started >= position { continue }
            let date = Date(timeIntervalSince1970: Double(state.updatedAtEpochMs) / 1000)
            result.append(GpodderEpisodeAction(
                podcast: GpodderSyncService.syncFeedURL(ref.feedUrl),
                episode: media,
                guid: ref.episodeId,
                action: "play",
                timestamp: GpodderEpisodeAction.formatTimestamp(date),
                started: started,
                position: position,
                total: total,
                device: deviceId
            ))
        }
        return result
    }
}
