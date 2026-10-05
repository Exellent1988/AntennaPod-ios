import Foundation

/// What to do with episodes that first appear on an **existing** subscription after refresh.
///
/// Distinct from Inbox (always derived: unplayed + not archived) and from global Auto-download
/// (new-ID cap after refresh). This action only touches **newly discovered** episode IDs.
enum NewEpisodeAction: String, CaseIterable, Identifiable, Codable, Hashable {
    /// Leave in Inbox only (default). No queue / download side effects.
    case inboxOnly
    /// Explicitly enqueue on the Queue tab (Inbox still lists them while unplayed).
    case addToQueue
    /// Enqueue on Queue and start a download via `DownloadService` (Wi‑Fi auto-DL gate).
    case addToQueueAndDownload

    var id: String { rawValue }

    var label: String {
        switch self {
        case .inboxOnly: return String(localized: "Inbox only")
        case .addToQueue: return String(localized: "Add to Queue")
        case .addToQueueAndDownload: return String(localized: "Add to Queue and download")
        }
    }

    var helpText: String {
        switch self {
        case .inboxOnly:
            return String(localized: "New episodes stay in Inbox (unplayed list). Nothing is added to Queue automatically.")
        case .addToQueue:
            return String(localized: "After refresh, newly appeared episodes are enqueued on Queue. Inbox still shows them while unplayed.")
        case .addToQueueAndDownload:
            return String(localized: "After refresh, newly appeared episodes are enqueued on Queue and downloaded (respects Auto-download Wi‑Fi only). Separate Auto-download rules may also enqueue newly appeared IDs (capped per feed).")
        }
    }
}

/// Per-feed override for new-episode action (Use global / Inbox / Queue).
/// Queue here means add-to-queue only — download stays a global choice when using Use global.
enum PerFeedNewEpisodeAction: String, CaseIterable, Identifiable, Codable, Hashable {
    case useGlobal
    case inboxOnly
    case addToQueue

    var id: String { rawValue }

    var label: String {
        switch self {
        case .useGlobal: return String(localized: "Use global")
        case .inboxOnly: return String(localized: "Inbox only")
        case .addToQueue: return String(localized: "Add to Queue")
        }
    }

    /// Resolve against the global Settings preference.
    func resolved(global: NewEpisodeAction) -> NewEpisodeAction {
        switch self {
        case .useGlobal: return global
        case .inboxOnly: return .inboxOnly
        case .addToQueue: return .addToQueue
        }
    }
}

/// Applies Inbox / Queue / Queue+download for newly discovered episodes after refresh.
@MainActor
enum NewEpisodeActionCoordinator {
    private static var isApplyInFlight = false

    /// Call after refresh collected `NewEpisodeBatch`es (existing subscriptions only).
    static func apply(
        _ batches: [NewEpisodeBatch],
        store: PodcastStore,
        downloads: DownloadService?,
        settings: AppSettings?
    ) async {
        guard let settings else { return }
        let flat = batches.filter { !$0.episodes.isEmpty }
        guard !flat.isEmpty else { return }
        guard !isApplyInFlight else { return }
        isApplyInFlight = true
        defer { isApplyInFlight = false }

        var downloadCandidates: [PodcastEpisode] = []

        for batch in flat {
            let feedSettings = store.feedSettings(for: batch.feedId)
            let action = feedSettings.newEpisodeAction
                .resolved(global: settings.newEpisodeAction)
            guard action != .inboxOnly else { continue }
            // Per-feed Auto-download Never blocks automatic downloads from this path too.
            // Queue enqueue still runs; Manual Download is unchanged.
            let allowAutomaticDownload = feedSettings.autoDownload != .never

            for episode in batch.episodes {
                store.enqueue(episode)
                if action == .addToQueueAndDownload, allowAutomaticDownload {
                    downloadCandidates.append(episode)
                }
            }
        }

        guard !downloadCandidates.isEmpty, let downloads else { return }

        AutoDownloadCoordinator.startNetworkMonitoringIfNeeded()
        // Same hold as auto-download: Wi‑Fi-only still enqueues `.automatic` downloads.
        // Dropping them here loses the batch — the next refresh does not treat these IDs as new.
        // Non-Wi‑Fi-only still skips a known-offline path.
        if !settings.autoDownloadWifiOnly {
            guard NetworkPathGate.shared.allowsTransfer(wifiOnly: false) else { return }
        }

        for episode in downloadCandidates {
            guard let url = episode.downloadUrl, !url.isEmpty else { continue }
            guard !downloads.isDownloaded(episode) else { continue }
            guard !downloads.inProgress.contains(episode.id) else { continue }
            await downloads.download(episode, source: .automatic)
        }
    }
}
