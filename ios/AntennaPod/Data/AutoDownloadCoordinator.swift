import Combine
import Foundation
import Network

/// Enqueues auto-downloads after feed refresh (global + per-feed overrides).
///
/// **Rules (this slice):**
/// 1. Per feed: `FeedSettings.autoDownload` Use global / Always / Never (Always/Never beat global).
/// 2. Only **newly appeared** episode IDs from the refresh that just completed (not the whole backlog).
/// 3. Among those newcomers: newest unplayed with a remote media URL, not already downloaded / in-flight,
///    capped by `autoDownloadEpisodesPerFeed` (1/2/3/5) **per feed**.
/// 4. Optional Wi‑Fi / Ethernet-only gate via `NWPathMonitor` (`autoDownloadWifiOnly`).
/// 5. Skips `local-folder://` / `file://` feeds and local file enclosures.
/// 6. Actual transfers go through `DownloadService.download` (`.automatic`) — storage-limit eviction unchanged.
///
/// Runs only after a successful refresh path that collected newcomers. No separate silent BGAppRefresh
/// download loop (BG fetch remains stubbed until Info.plist adds `fetch`).
@MainActor
enum AutoDownloadCoordinator {
    /// Prevents overlapping enqueue from concurrent refresh completions.
    private static var isEnqueueInFlight = false

    /// Start path monitoring once (idempotent). Safe to call from app launch.
    static func startNetworkMonitoringIfNeeded() {
        NetworkPathGate.shared.startIfNeeded()
    }

    /// After a full or partial feed refresh: enqueue eligible **new** episodes only.
    ///
    /// - Parameter newBatches: Newly discovered episodes from this refresh (existing subscriptions).
    ///   Empty batches → no auto-download (avoids backlog storms when the toggle is flipped on).
    static func enqueueAfterRefresh(
        store: PodcastStore,
        downloads: DownloadService?,
        settings: AppSettings?,
        newBatches: [NewEpisodeBatch]
    ) async {
        guard let downloads, let settings else { return }
        let flat = newBatches.filter { !$0.episodes.isEmpty }
        guard !flat.isEmpty else { return }
        guard !isEnqueueInFlight else { return }
        isEnqueueInFlight = true
        defer { isEnqueueInFlight = false }

        let globalOn = settings.autoDownloadEnabled
        startNetworkMonitoringIfNeeded()
        guard NetworkPathGate.shared.allowsAutoDownload(wifiOnly: settings.autoDownloadWifiOnly) else {
            return
        }

        let cap = settings.autoDownloadEpisodesPerFeed.rawValue
        var candidates: [PodcastEpisode] = []
        for batch in flat {
            guard let feed = store.feeds.first(where: { $0.id == batch.feedId })
                ?? store.feeds.first(where: { $0.feedUrl == batch.feedUrl })
            else { continue }
            guard !LocalFolderFeed.isLocalFolderFeed(feed) else { continue }
            guard store.feedSettings(for: feed.id).allowsAutoDownload(globalEnabled: globalOn) else {
                continue
            }
            candidates.append(
                contentsOf: eligibleNewEpisodes(
                    newcomers: batch.episodes,
                    store: store,
                    downloads: downloads,
                    cap: cap
                )
            )
        }
        for episode in candidates {
            await downloads.download(episode, source: .automatic)
        }
    }

    /// Newest-first among **newcomer** IDs only: unplayed, not downloaded / in progress,
    /// remote media URL, limited to `cap`.
    static func eligibleNewEpisodes(
        newcomers: [PodcastEpisode],
        store: PodcastStore,
        downloads: DownloadService,
        cap: Int
    ) -> [PodcastEpisode] {
        let sorted = newcomers.sorted { lhs, rhs in
            let l = lhs.pubDateEpochMs ?? Int64.min
            let r = rhs.pubDateEpochMs ?? Int64.min
            if l != r { return l > r }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        var picked: [PodcastEpisode] = []
        for episode in sorted {
            guard picked.count < cap else { break }
            guard episode.downloadUrl != nil, !(episode.downloadUrl ?? "").isEmpty else { continue }
            guard !LocalFolderFeed.isLocalFileDownloadURL(episode.downloadUrl) else { continue }
            guard !store.isPlayed(episode.id) else { continue }
            guard !store.isArchived(episode.id) else { continue }
            guard !downloads.isDownloaded(episode) else { continue }
            guard !downloads.inProgress.contains(episode.id) else { continue }
            picked.append(episode)
        }
        return picked
    }
}

// MARK: - NWPathMonitor gate

/// Coarse network kind for Settings → Network / Downloads status (honesty only — not VPN/proxy).
enum NetworkPathKind: Equatable {
    case offline
    case wifi
    case ethernet
    case cellular
    case other

    var statusLabel: String {
        switch self {
        case .offline: return String(localized: "Offline")
        case .wifi: return String(localized: "Wi‑Fi")
        case .ethernet: return String(localized: "Ethernet")
        case .cellular: return String(localized: "Cellular")
        case .other: return String(localized: "Other network")
        }
    }

    var accessibilityLabel: String {
        String(localized: "Current network") + ": " + statusLabel
    }
}

/// Shared path monitor for Settings → Network / Downloads Wi‑Fi-only policies
/// (auto-download, manual download, streaming). Publishes path changes for Settings status.
@MainActor
final class NetworkPathGate: ObservableObject {
    static let shared = NetworkPathGate()

    private let monitor = NWPathMonitor()
    private var started = false
    /// Optimistic defaults until the first path callback (avoids blocking cold start).
    @Published private(set) var pathSatisfied = true
    @Published private(set) var isWifiOrEthernet = true
    @Published private(set) var kind: NetworkPathKind = .wifi
    /// False until the first `NWPath` callback. `kind` stays the optimistic `.wifi`
    /// default so cold-start `allowsTransfer` is unchanged; Settings must not present
    /// that default as a measured Wi‑Fi path.
    @Published private(set) var hasReportedPath = false

    private init() {}

    func startIfNeeded() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.apply(path)
            }
        }
        monitor.start(queue: DispatchQueue(label: "de.danoeh.antennapod.ios.network-path", qos: .utility))
    }

    private func apply(_ path: NWPath) {
        hasReportedPath = true
        pathSatisfied = path.status == .satisfied
        let wifi = path.usesInterfaceType(.wifi)
        let ethernet = path.usesInterfaceType(.wiredEthernet)
        isWifiOrEthernet = wifi || ethernet
        if !pathSatisfied {
            kind = .offline
        } else if wifi {
            kind = .wifi
        } else if ethernet {
            kind = .ethernet
        } else if path.usesInterfaceType(.cellular) {
            kind = .cellular
        } else {
            kind = .other
        }
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
