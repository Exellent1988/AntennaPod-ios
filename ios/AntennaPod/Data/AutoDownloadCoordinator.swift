import Foundation
import Network

/// Enqueues auto-downloads after feed refresh (global + per-feed overrides).
///
/// **Rules (this slice):**
/// 1. Per feed: `FeedSettings.autoDownload` Use global / Always / Never (Always/Never beat global).
/// 2. Per feed: newest unplayed episodes with a media URL, not already downloaded / in-flight,
///    capped by `autoDownloadEpisodesPerFeed` (1/2/3/5).
/// 3. Optional Wi‑Fi / Ethernet-only gate via `NWPathMonitor` (`autoDownloadWifiOnly`).
/// 4. Actual transfers go through `DownloadService.download` — storage-limit eviction unchanged.
@MainActor
enum AutoDownloadCoordinator {
    /// Prevents overlapping enqueue from concurrent refresh completions.
    private static var isEnqueueInFlight = false

    /// Start path monitoring once (idempotent). Safe to call from app launch.
    static func startNetworkMonitoringIfNeeded() {
        NetworkPathGate.shared.startIfNeeded()
    }

    /// After a full or partial feed refresh: enqueue eligible episodes for all current feeds.
    static func enqueueAfterRefresh(
        store: PodcastStore,
        downloads: DownloadService?,
        settings: AppSettings?
    ) async {
        guard let downloads, let settings else { return }
        guard !isEnqueueInFlight else { return }
        isEnqueueInFlight = true
        defer { isEnqueueInFlight = false }

        let globalOn = settings.autoDownloadEnabled
        let eligibleFeeds = store.feeds.filter {
            store.feedSettings(for: $0.id).allowsAutoDownload(globalEnabled: globalOn)
        }
        guard !eligibleFeeds.isEmpty else { return }

        startNetworkMonitoringIfNeeded()
        guard NetworkPathGate.shared.allowsAutoDownload(wifiOnly: settings.autoDownloadWifiOnly) else {
            return
        }

        let cap = settings.autoDownloadEpisodesPerFeed.rawValue
        var candidates: [PodcastEpisode] = []
        for feed in eligibleFeeds {
            candidates.append(contentsOf: eligibleEpisodes(in: feed, store: store, downloads: downloads, cap: cap))
        }
        for episode in candidates {
            await downloads.download(episode, source: .automatic)
        }
    }

    /// Newest-first unplayed, not downloaded / in progress, with a media URL, limited to `cap`.
    static func eligibleEpisodes(
        in feed: PodcastFeed,
        store: PodcastStore,
        downloads: DownloadService,
        cap: Int
    ) -> [PodcastEpisode] {
        let sorted = feed.episodes.sorted { lhs, rhs in
            let l = lhs.pubDateEpochMs ?? Int64.min
            let r = rhs.pubDateEpochMs ?? Int64.min
            if l != r { return l > r }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        var picked: [PodcastEpisode] = []
        for episode in sorted {
            guard picked.count < cap else { break }
            guard episode.downloadUrl != nil, !(episode.downloadUrl ?? "").isEmpty else { continue }
            guard !store.isPlayed(episode.id) else { continue }
            guard !downloads.isDownloaded(episode) else { continue }
            guard !downloads.inProgress.contains(episode.id) else { continue }
            picked.append(episode)
        }
        return picked
    }
}

// MARK: - NWPathMonitor gate

/// Shared path monitor for Settings → Network / Downloads Wi‑Fi-only policies
/// (auto-download, manual download, streaming).
@MainActor
final class NetworkPathGate {
    static let shared = NetworkPathGate()

    private let monitor = NWPathMonitor()
    private var started = false
    /// Optimistic defaults until the first path callback (avoids blocking cold start).
    private(set) var pathSatisfied = true
    private(set) var isWifiOrEthernet = true

    private init() {}

    func startIfNeeded() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.pathSatisfied = path.status == .satisfied
                self.isWifiOrEthernet =
                    path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
            }
        }
        monitor.start(queue: DispatchQueue(label: "de.danoeh.antennapod.ios.network-path", qos: .utility))
    }

    /// When `wifiOnly` is true, requires a satisfied Wi‑Fi or Ethernet path.
    /// When false, only requires a satisfied path (cellular OK).
    func allowsTransfer(wifiOnly: Bool) -> Bool {
        guard pathSatisfied else { return false }
        if wifiOnly {
            return isWifiOrEthernet
        }
        return true
    }

    /// Auto-download Wi‑Fi-only gate (same as `allowsTransfer`).
    func allowsAutoDownload(wifiOnly: Bool) -> Bool {
        allowsTransfer(wifiOnly: wifiOnly)
    }
}
