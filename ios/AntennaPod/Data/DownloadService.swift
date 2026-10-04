import CryptoKit
import Foundation

struct DownloadedEpisode: Identifiable, Hashable, Codable {
    let episode: PodcastEpisode
    /// File name under `DownloadService.downloadsDirectory` (not an absolute path).
    let fileName: String
    /// Wall-clock when the offline file finished downloading (ms since epoch).
    /// Absent in older `downloads.json` rows; may be backfilled from file creation/mtime once.
    var downloadedAtEpochMs: Int64?

    init(episode: PodcastEpisode, fileName: String, downloadedAtEpochMs: Int64? = nil) {
        self.episode = episode
        self.fileName = fileName
        self.downloadedAtEpochMs = downloadedAtEpochMs
    }

    var id: String { episode.id }

    var localFileURL: URL {
        DownloadService.downloadsDirectory.appendingPathComponent(fileName)
    }

    /// Downloads list sort key: prefer stored download completion, else episode `pubDateEpochMs`.
    var downloadsSortEpochMs: Int64? {
        downloadedAtEpochMs ?? episode.pubDateEpochMs
    }

    /// Best-effort proxy from the offline file (creation, else content modification).
    func fileDownloadProxyEpochMs() -> Int64? {
        let values = try? localFileURL.resourceValues(forKeys: [
            .creationDateKey, .contentModificationDateKey
        ])
        guard let date = values?.creationDate ?? values?.contentModificationDate else {
            return nil
        }
        return Int64(date.timeIntervalSince1970 * 1000)
    }

    /// Bytes on disk for the offline file (`fileSize` resource value). `nil` if missing or unreadable.
    func localFileByteSize() -> Int64? {
        let values = try? localFileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values?.isRegularFile != false,
              let size = values?.fileSize,
              size > 0 else {
            return nil
        }
        return Int64(size)
    }

    /// Prefer local file size; else feed enclosure `PodcastEpisode.size` when > 0. Hide when unknown.
    func knownByteSize() -> Int64? {
        if let local = localFileByteSize() {
            return local
        }
        if episode.size > 0 {
            return episode.size
        }
        return nil
    }

    /// Compact KB/MB/GB via `DownloadStorageUsage.formatBytes` when `knownByteSize` is set.
    var formattedKnownByteSize: String? {
        guard let bytes = knownByteSize() else { return nil }
        return DownloadStorageUsage.formatBytes(bytes)
    }
}

/// Persisted in-flight background task ↔ episode mapping.
/// `feedId` (optional) helps HTTP Basic auth challenges look up Keychain credentials —
/// never stores username/password (those stay in Keychain only).
struct PendingDownloadMapping: Codable, Hashable {
    var taskIdentifier: Int
    var episode: PodcastEpisode
    var fileName: String
    /// Owning subscription id when known (for Keychain HTTP Basic on challenge). Not a secret.
    var feedId: UUID?

    init(
        taskIdentifier: Int,
        episode: PodcastEpisode,
        fileName: String,
        feedId: UUID? = nil
    ) {
        self.taskIdentifier = taskIdentifier
        self.episode = episode
        self.fileName = fileName
        self.feedId = feedId
    }

    private enum CodingKeys: String, CodingKey {
        case taskIdentifier, episode, fileName, feedId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        taskIdentifier = try c.decode(Int.self, forKey: .taskIdentifier)
        episode = try c.decode(PodcastEpisode.self, forKey: .episode)
        fileName = try c.decode(String.self, forKey: .fileName)
        feedId = try c.decodeIfPresent(UUID.self, forKey: .feedId)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(taskIdentifier, forKey: .taskIdentifier)
        try c.encode(episode, forKey: .episode)
        try c.encode(fileName, forKey: .fileName)
        try c.encodeIfPresent(feedId, forKey: .feedId)
    }
}

/// One failed download attempt (ring-buffered in Application Support).
struct DownloadErrorEntry: Identifiable, Hashable, Codable {
    let id: UUID
    let episodeId: String
    let episodeTitle: String
    let feedTitle: String
    let message: String
    let timestampEpochMs: Int64

    init(
        id: UUID = UUID(),
        episodeId: String,
        episodeTitle: String,
        feedTitle: String,
        message: String,
        timestampEpochMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.id = id
        self.episodeId = episodeId
        self.episodeTitle = episodeTitle
        self.feedTitle = feedTitle
        self.message = message
        self.timestampEpochMs = timestampEpochMs
    }

    var timestamp: Date {
        Date(timeIntervalSince1970: TimeInterval(timestampEpochMs) / 1000)
    }
}


/// Snapshot of Documents/downloads size for Settings UI.
struct DownloadStorageUsage: Equatable {
    var usedBytes: Int64
    var fileCount: Int
    var limitBytes: Int64?

    var isOverLimit: Bool {
        guard let limitBytes else { return false }
        return usedBytes > limitBytes
    }

    var usedFormatted: String {
        Self.formatBytes(usedBytes)
    }

    var limitFormatted: String? {
        guard let limitBytes else { return nil }
        return Self.formatBytes(limitBytes)
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

/// Distinguishes user-tapped downloads from auto-download enqueue (separate Wi‑Fi policies).
enum DownloadEnqueueSource {
    case manual
    case automatic
}

/// One episode waiting for a free parallel-download slot (in-memory FIFO).
private struct WaitingDownload {
    var episode: PodcastEpisode
    var source: DownloadEnqueueSource
}

@MainActor
final class DownloadService: ObservableObject {
    static let backgroundSessionIdentifier = "de.danoeh.antennapod.ios.background-downloads"

    static let downloadsDirectory: URL = {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    @Published var downloads: [DownloadedEpisode] = []
    @Published var inProgress: Set<String> = []
    @Published var lastError: String?
    /// Recent download failures (newest first; Application Support ring buffer).
    @Published private(set) var recentErrors: [DownloadErrorEntry] = []
    /// Last measured size of the downloads folder (refreshed on load / eviction / settings).
    @Published private(set) var storageUsage = DownloadStorageUsage(usedBytes: 0, fileCount: 0, limitBytes: nil)

    static let downloadErrorRingCapacity = 50

    /// Bound from the app so eviction can prefer played episodes and skip favorites / queue.
    weak var store: PodcastStore?
    /// Bound for the configured byte budget.
    weak var settings: AppSettings?

    private let sessionDelegate = DownloadSessionDelegate()
    private var session: URLSession!
    /// Retains block-based observer for `AppHTTPProxy.didChangeNotification`.
    private var proxyChangeObserver: NSObjectProtocol?
    /// Live task id → episode (+ destination file name).
    private var pendingByTaskId: [Int: PendingDownloadMapping] = [:]
    /// Episodes accepted but not yet started as URLSession tasks (FIFO). In-memory only —
    /// survives while the service is alive / session completion handlers fire; not written to disk.
    private var waitingQueue: [WaitingDownload] = []
    private var backgroundCompletionHandler: (() -> Void)?

    private static weak var activeInstance: DownloadService?
    private static var pendingBackgroundCompletionHandler: (() -> Void)?

    init() {
        let config = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.allowsCellularAccess = true
        AppURLSession.applyProxy(to: config)
        session = URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
        sessionDelegate.owner = self

        Self.activeInstance = self
        if let pending = Self.pendingBackgroundCompletionHandler {
            backgroundCompletionHandler = pending
            Self.pendingBackgroundCompletionHandler = nil
        }

        proxyChangeObserver = NotificationCenter.default.addObserver(
            forName: AppHTTPProxy.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.recreateSessionIfIdleForProxyChange()
        }

        reloadFromDisk()
        reconnectOutstandingTasks()
        refreshStorageUsage()
        recentErrors = PodcastPersistence.loadDownloadErrors()
        NetworkPathGate.shared.onPathApplied = { [weak self] in
            self?.pumpWaitingQueue()
        }
    }

    /// Background sessions cannot mutate `connectionProxyDictionary` in place.
    /// When idle (no live tasks / waiting queue), invalidate and recreate so the new proxy applies.
    /// If downloads are active, the next cold start / idle recreate picks it up — honest beta limit.
    private func recreateSessionIfIdleForProxyChange() {
        guard pendingByTaskId.isEmpty, waitingQueue.isEmpty else { return }
        let old = session
        old?.finishTasksAndInvalidate()
        let config = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.allowsCellularAccess = true
        AppURLSession.applyProxy(to: config)
        session = URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
    }

    /// Called from `AppDelegate` when iOS relaunches / wakes the app for this background session.
    static func registerBackgroundCompletionHandler(_ handler: @escaping () -> Void) {
        if let active = activeInstance {
            active.backgroundCompletionHandler = handler
        } else {
            pendingBackgroundCompletionHandler = handler
        }
    }

    func localURL(for episode: PodcastEpisode) -> URL? {
        if let item = downloads.first(where: { $0.id == episode.id }) {
            let url = item.localFileURL
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        // Local folder feeds: enclosure is already a file:// URL on disk.
        if let raw = episode.downloadUrl,
           let url = URL(string: raw),
           url.isFileURL,
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }

    func isDownloaded(_ episode: PodcastEpisode) -> Bool {
        localURL(for: episode) != nil
    }

    static let manualCellularBlockedMessage = String(
        localized: "Manual downloads are Wi‑Fi only. Connect to Wi‑Fi or Ethernet, or turn off Manual download Wi‑Fi only in Settings → Network / Downloads."
    )

    /// Default soft cap for Feed detail **Download all unplayed** when no setting is passed
    /// (matches `FeedDownloadUnplayedSoftCap.fifty` / prior hard soft-cap of 50).
    static let feedDownloadAllCap = FeedDownloadUnplayedSoftCap.fifty.rawValue

    /// Episodes on `feed` eligible for manual bulk **Download all unplayed**: unplayed, not
    /// archived, not already downloaded / in-flight, with an **http(s)** media enclosure
    /// (skips local-folder `file://` and non-http schemes). Newest `pubDateEpochMs` first,
    /// limited to `cap` (default `feedDownloadAllCap` / settings default 50). Cap is always
    /// ≥1 — callers pass `AppSettings.feedDownloadUnplayedSoftCap.episodeCap`. Full-feed
    /// catalog — not chip/search.
    func eligibleForFeedDownloadAll(
        in feed: PodcastFeed,
        store: PodcastStore,
        cap: Int = DownloadService.feedDownloadAllCap
    ) -> [PodcastEpisode] {
        let effectiveCap = max(1, cap)
        let sorted = feed.episodes.sorted { lhs, rhs in
            let l = lhs.pubDateEpochMs ?? Int64.min
            let r = rhs.pubDateEpochMs ?? Int64.min
            if l != r { return l > r }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        var picked: [PodcastEpisode] = []
        for episode in sorted {
            guard picked.count < effectiveCap else { break }
            guard let raw = episode.downloadUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty,
                  let url = URL(string: raw) else { continue }
            let scheme = url.scheme?.lowercased()
            guard scheme == "http" || scheme == "https" else { continue }
            guard !LocalFolderFeed.isLocalFileDownloadURL(raw) else { continue }
            guard !store.isPlayed(episode.id) else { continue }
            guard !store.isArchived(episode.id) else { continue }
            guard !isDownloaded(episode) else { continue }
            guard !inProgress.contains(episode.id) else { continue }
            picked.append(episode)
        }
        return picked
    }

    /// Enqueues manual downloads for many episodes. Honors `manualDownloadWifiOnly` **once**
    /// up front — on block sets the same `lastError` / error-log path as a single manual
    /// download and does not enqueue. Does not delete existing downloads.
    func downloadAllManual(_ episodes: [PodcastEpisode]) async {
        guard !episodes.isEmpty else { return }
        if settings?.manualDownloadWifiOnly == true {
            AutoDownloadCoordinator.startNetworkMonitoringIfNeeded()
            if !NetworkPathGate.shared.allowsTransfer(wifiOnly: true) {
                // Same feedback path as `download(_:source: .manual)` cellular block.
                if let first = episodes.first {
                    recordFailure(episode: first, message: Self.manualCellularBlockedMessage)
                } else {
                    lastError = Self.manualCellularBlockedMessage
                }
                return
            }
        }
        for episode in episodes {
            await download(episode, source: .manual)
        }
    }

    /// Enqueues an episode for download. Honors `maxParallelDownloads`: only that many
    /// `URLSession` tasks run at once; extras wait in an in-memory FIFO until a slot frees.
    /// Active tasks continue while the app is suspended (system-permitting); mapping is
    /// persisted for relaunch. Waiting (not-yet-started) items are **not** persisted —
    /// they are dropped if the process dies before a slot opens.
    /// - Parameter source: `.manual` (default) honors `manualDownloadWifiOnly`; `.automatic`
    ///   skips that manual gate. With `autoDownloadWifiOnly`, automatic items stay in the
    ///   waiting FIFO until a real Wi‑Fi/Ethernet path is reported (not the optimistic default).
    func download(_ episode: PodcastEpisode, source: DownloadEnqueueSource = .manual) async {
        guard let remote = episode.downloadUrl, let url = URL(string: remote) else {
            recordFailure(episode: episode, message: String(localized: "Episode has no media URL"))
            return
        }
        // Already-local folder files — treat as present; do not start a network transfer.
        if url.isFileURL {
            if FileManager.default.fileExists(atPath: url.path) {
                lastError = nil
            } else {
                recordFailure(episode: episode, message: String(localized: "Local file missing"))
            }
            return
        }
        if inProgress.contains(episode.id) {
            return
        }
        if source == .manual, settings?.manualDownloadWifiOnly == true {
            AutoDownloadCoordinator.startNetworkMonitoringIfNeeded()
            if !NetworkPathGate.shared.allowsTransfer(wifiOnly: true) {
                recordFailure(episode: episode, message: Self.manualCellularBlockedMessage)
                return
            }
        }
        lastError = nil
        inProgress.insert(episode.id)
        waitingQueue.append(WaitingDownload(episode: episode, source: source))
        pumpWaitingQueue()
    }

    /// Start waiting downloads until active `URLSession` tasks reach `maxParallelDownloads`.
    /// Call after enqueue, task completion/cancel, and when the Settings cap changes.
    func pumpWaitingQueue() {
        let limit = settings?.maxParallelDownloads.rawValue ?? MaxParallelDownloads.three.rawValue
        var heldForWifi: [WaitingDownload] = []
        while !waitingQueue.isEmpty && pendingByTaskId.count < limit {
            let next = waitingQueue.removeFirst()
            // Re-check manual Wi‑Fi gate when a waiting item finally starts (path may have changed).
            if next.source == .manual, settings?.manualDownloadWifiOnly == true {
                AutoDownloadCoordinator.startNetworkMonitoringIfNeeded()
                if !NetworkPathGate.shared.allowsTransfer(wifiOnly: true) {
                    inProgress.remove(next.episode.id)
                    recordFailure(episode: next.episode, message: Self.manualCellularBlockedMessage)
                    continue
                }
            }
            // Auto-download Wi‑Fi-only is not the optimistic pre-callback default, and it is
            // rechecked when a parallel slot opens. Held items stay in progress so Cancel works.
            if next.source == .automatic, settings?.autoDownloadWifiOnly == true {
                AutoDownloadCoordinator.startNetworkMonitoringIfNeeded()
                let gate = NetworkPathGate.shared
                if !gate.hasReportedPath || !gate.allowsTransfer(wifiOnly: true) {
                    heldForWifi.append(next)
                    continue
                }
            }
            startActiveDownload(episode: next.episode)
        }
        if !heldForWifi.isEmpty {
            waitingQueue.insert(contentsOf: heldForWifi, at: 0)
        }
    }


    /// Documents filename for a finished download.
    /// Percent-encoding the episode id keeps the historical name when it fits.
    /// A long permalink guid expands past the 255-byte name limit, and the
    /// temp→Documents move then fails after a successful transfer. Those ids
    /// use a SHA-256 name instead (same id always maps to the same file).
    private static func storageFileName(episodeId: String, pathExtension ext: String) -> String {
        let encoded = episodeId.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        if !encoded.isEmpty {
            let candidate = "\(encoded).\(ext)"
            if candidate.lengthOfBytes(using: .utf8) <= 255 {
                return candidate
            }
        }
        let digest = SHA256.hash(data: Data(episodeId.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        var suffix = ""
        for scalar in ext.unicodeScalars where CharacterSet.alphanumerics.contains(scalar) {
            suffix.unicodeScalars.append(scalar)
            if suffix.count == 8 { break }
        }
        return "\(hex).\(suffix.isEmpty ? "mp3" : suffix)"
    }

    /// Hands one episode to the background `URLSession` (caller already reserved an `inProgress` slot).
    /// When the owning feed has HTTP Basic credentials in Keychain **and** the media URL host
    /// matches the feed URL host, attaches `Authorization` (never logged). Other CDN hosts are
    /// left unauthenticated (honest). Local-folder `file://` never uses HTTP auth.
    private func startActiveDownload(episode: PodcastEpisode) {
        guard let remote = episode.downloadUrl, let url = URL(string: remote), !url.isFileURL else {
            inProgress.remove(episode.id)
            recordFailure(episode: episode, message: String(localized: "Episode has no media URL"))
            return
        }

        let ext = url.pathExtension.isEmpty ? "mp3" : url.pathExtension
        let fileName = Self.storageFileName(episodeId: episode.id, pathExtension: ext)

        var request = URLRequest(url: url)
        AppUserAgent.apply(to: &request)
        if let creds = httpBasicCredentialsForDownload(episode: episode, mediaURL: url) {
            FeedHttpBasicAuth.apply(creds, to: &request)
        }

        let owningFeedId = store?.feed(containingEpisodeId: episode.id)?.id
        let task = session.downloadTask(with: request)
        let mapping = PendingDownloadMapping(
            taskIdentifier: task.taskIdentifier,
            episode: episode,
            fileName: fileName,
            feedId: owningFeedId
        )
        pendingByTaskId[task.taskIdentifier] = mapping
        sessionDelegate.setPending(mapping, for: task.taskIdentifier)
        persistPending()
        task.resume()
    }

    /// Keychain credentials when media host matches the owning feed host.
    func httpBasicCredentialsForDownload(
        episode: PodcastEpisode,
        mediaURL: URL
    ) -> FeedHttpBasicCredentials? {
        guard let feed = store?.feed(containingEpisodeId: episode.id) else { return nil }
        guard !LocalFolderFeed.isLocalFolderFeed(feed) else { return nil }
        guard let creds = FeedHttpBasicAuthKeychain.load(for: feed.id), creds.isUsable else {
            return nil
        }
        guard FeedHttpBasicAuth.hostMatches(requestURL: mediaURL, feedURLString: feed.feedUrl) else {
            return nil
        }
        return creds
    }

    /// Replace catalog episode metadata for ids present in `freshById` (feed refresh / rescan).
    /// Keeps `fileName` and `downloadedAtEpochMs`. Does not delete or re-download the file.
    /// Empty refreshed chapters keep a non-empty catalog chapter list (lazy fetch not in RSS).
    func replaceEpisodeSnapshots(with freshById: [String: PodcastEpisode]) {
        guard !freshById.isEmpty, !downloads.isEmpty else { return }
        var next = downloads
        var changed = false
        for index in next.indices {
            let item = next[index]
            guard let fresh = freshById[item.id] else { continue }
            var merged = fresh
            if merged.chapters.isEmpty, !item.episode.chapters.isEmpty {
                merged.chapters = item.episode.chapters
            }
            guard merged != item.episode else { continue }
            next[index] = DownloadedEpisode(
                episode: merged,
                fileName: item.fileName,
                downloadedAtEpochMs: item.downloadedAtEpochMs
            )
            changed = true
        }
        guard changed else { return }
        downloads = next
        persistCompleted()
    }

    func delete(_ episode: PodcastEpisode) {
        cancelTask(for: episode.id)
        if let existing = downloads.first(where: { $0.id == episode.id }) {
            try? FileManager.default.removeItem(at: existing.localFileURL)
            downloads.removeAll { $0.id == episode.id }
            persistCompleted()
        }
        inProgress.remove(episode.id)
        refreshStorageUsage()
    }

    /// Cancels an in-flight background download for `episode`. No-op if none is pending.
    /// Does not remove a completed offline file (use `delete`).
    func cancelDownload(_ episode: PodcastEpisode) {
        cancelTask(for: episode.id)
    }

    /// Count of downloads that `cancelAllInFlightDownloads` would cancel: active `URLSession`
    /// tasks + waiting FIFO items. Equals `inProgress.count` in steady state (published for UI).
    var cancelAllInFlightCount: Int {
        inProgress.count
    }

    /// Cancels **every** in-flight background download and clears the waiting FIFO.
    /// Does **not** delete completed offline files (use `deleteAllDownloads` / `delete`).
    /// Does not touch played status, queue, favorites, or history. Confirmation is UI
    /// responsibility. Returns how many episode ids were cancelled (pre-clear `inProgress` size).
    @discardableResult
    func cancelAllInFlightDownloads() -> Int {
        let count = inProgress.count
        // Snapshot task ids before clearing maps so async cancel still targets the right tasks.
        let taskIds = Array(pendingByTaskId.keys)
        waitingQueue.removeAll()
        pendingByTaskId.removeAll()
        sessionDelegate.removeAllPending()
        persistPending()
        inProgress.removeAll()
        if !taskIds.isEmpty {
            session.getTasksWithCompletionHandler { _, _, downloadTasks in
                for task in downloadTasks where taskIds.contains(task.taskIdentifier) {
                    task.cancel()
                }
            }
        }
        // Do not pumpWaitingQueue — waiting was cleared intentionally.
        return count
    }

    /// Completed downloads marked **played**, excluding favorited / starred episodes.
    /// Matches auto-delete-after-playing favorite protection (`PodcastStore.isFavorite`).
    /// Unplayed downloads are never included.
    func playedDownloadsEligibleForDelete(store: PodcastStore? = nil) -> [DownloadedEpisode] {
        let s = store ?? self.store
        return downloads.filter { item in
            guard s?.isPlayed(item.id) == true else { return false }
            // Same as auto-delete-after-playing: keep favorited offline files.
            guard s?.isFavorite(item.id) != true else { return false }
            return true
        }
    }

    /// Approximate total byte size of files that `deletePlayedDownloads` would remove.
    func playedDownloadsEligibleByteSize(store: PodcastStore? = nil) -> Int64 {
        var total: Int64 = 0
        for item in playedDownloadsEligibleForDelete(store: store) {
            let values = try? item.localFileURL.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    /// Deletes local files for played (non-favorite) downloads via the single-delete path (`delete(_:)`).
    /// Does **not** mark unplayed, clear the queue, or remove unplayed / favorited downloads.
    /// Confirmation is UI responsibility. Returns how many files were deleted.
    @discardableResult
    func deletePlayedDownloads(store: PodcastStore? = nil) -> Int {
        let victims = playedDownloadsEligibleForDelete(store: store)
        for item in victims {
            delete(item.episode)
        }
        return victims.count
    }

    /// Approximate total byte size of files that `deleteAllDownloads` would remove (full completed catalog).
    /// Uses on-disk `fileSize` when readable; missing files contribute 0 (same honesty as played-delete size).
    func completedDownloadsByteSize() -> Int64 {
        var total: Int64 = 0
        for item in downloads {
            let values = try? item.localFileURL.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    /// Deletes **every** completed offline file in the Downloads catalog — including favorited / starred
    /// episodes (unlike `deletePlayedDownloads` / auto-delete, which skip favorites). Local files only:
    /// does **not** mark unplayed, clear the queue, remove favorites/history entries, or stop playback.
    /// Uses the same single-episode `delete(_:)` path as swipe / player deletion, including its
    /// cancellation, catalog persistence, and storage refresh behavior. Confirmation is UI responsibility.
    @discardableResult
    func deleteAllDownloads() -> Int {
        let victims = downloads
        for item in victims {
            delete(item.episode)
        }
        return victims.count
    }

    /// Completed downloads whose episode id appears in `feed.episodes` (this feed’s current catalog)
    /// or is a channel trailer for this feed (`podcast-trailer:<feedUUID>:`).
    /// Does not include other podcasts’ files. Local-folder `file://` episodes are usually not in the
    /// Downloads catalog (already on disk outside `Documents/downloads`).
    func downloads(forFeed feed: PodcastFeed) -> [DownloadedEpisode] {
        let ids = Set(feed.episodes.map(\.id))
        let trailerPrefix = PodcastTrailer.playbackEpisodeIdPrefix(feedId: feed.id)
        return downloads.filter { ids.contains($0.id) || $0.id.hasPrefix(trailerPrefix) }
    }

    /// Approximate total byte size of files that `deleteDownloads(forFeed:)` would remove.
    /// Uses on-disk `fileSize` when readable; missing files contribute 0 (same honesty as Delete all downloads).
    func downloadsByteSize(forFeed feed: PodcastFeed) -> Int64 {
        var total: Int64 = 0
        for item in downloads(forFeed: feed) {
            let values = try? item.localFileURL.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    /// Deletes offline files for episodes currently listed on `feed`, and cancels in-flight downloads
    /// for those episode ids. Walks the single-delete path (`delete(_:)`).
    /// Does **not** unsubscribe, clear queue / favorites / history, mark played, or touch other feeds’
    /// downloads. Confirmation and ordering vs `PodcastStore.unsubscribe` are UI responsibility —
    /// call **before** unsubscribe so episode ids are still on the feed. Returns how many completed
    /// catalog files were deleted.
    @discardableResult
    func deleteDownloads(forFeed feed: PodcastFeed) -> Int {
        let episodeIds = Set(feed.episodes.map(\.id))
        let trailerPrefix = PodcastTrailer.playbackEpisodeIdPrefix(feedId: feed.id)
        func belongs(_ episodeId: String) -> Bool {
            episodeIds.contains(episodeId) || episodeId.hasPrefix(trailerPrefix)
        }
        var ids = episodeIds
        for item in downloads where belongs(item.id) {
            ids.insert(item.id)
        }
        for id in inProgress where belongs(id) {
            ids.insert(id)
        }
        for waiting in waitingQueue where belongs(waiting.episode.id) {
            ids.insert(waiting.episode.id)
        }
        guard !ids.isEmpty else { return 0 }
        for id in ids {
            cancelTask(for: id)
        }
        let victims = downloads.filter { belongs($0.id) }
        for item in victims {
            delete(item.episode)
        }
        for id in ids {
            inProgress.remove(id)
        }
        return victims.count
    }

    /// Completed downloads for this feed that are **not** favorited / starred.
    /// Matches auto-delete-after-playing and Downloads **Delete played** favorite protection
    /// (`PodcastStore.isFavorite`). Favorited offline files for this feed are never included.
    /// Full feed catalog membership via `downloads(forFeed:)` — not chip/search filtered.
    func downloadsEligibleForDelete(forFeed feed: PodcastFeed, store: PodcastStore? = nil) -> [DownloadedEpisode] {
        let s = store ?? self.store
        return downloads(forFeed: feed).filter { item in
            // Same as auto-delete-after-playing / Delete played: keep favorited offline files.
            s?.isFavorite(item.id) != true
        }
    }

    /// Approximate total byte size of files that `deleteEligibleDownloads(forFeed:)` would remove.
    /// Uses on-disk `fileSize` when readable; missing files contribute 0 (same honesty as Delete all downloads).
    func downloadsEligibleByteSize(forFeed feed: PodcastFeed, store: PodcastStore? = nil) -> Int64 {
        var total: Int64 = 0
        for item in downloadsEligibleForDelete(forFeed: feed, store: store) {
            let values = try? item.localFileURL.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    /// Deletes offline files for this feed’s completed downloads **except favorites**, via the
    /// single-delete path (`delete(_:)`). Skips favorited / starred episodes like auto-delete /
    /// Delete played downloads. Does **not** unsubscribe, clear queue / favorites / history /
    /// archive, mark played/unplayed, or touch other feeds’ downloads. Confirmation is UI
    /// responsibility. Returns how many completed catalog files were deleted.
    @discardableResult
    func deleteEligibleDownloads(forFeed feed: PodcastFeed, store: PodcastStore? = nil) -> Int {
        let victims = downloadsEligibleForDelete(forFeed: feed, store: store)
        for item in victims {
            delete(item.episode)
        }
        return victims.count
    }

    /// Recompute folder usage from disk + apply configured limit for the Settings display.
    @discardableResult
    func refreshStorageUsage() -> DownloadStorageUsage {
        let limit = settings?.downloadStorageLimit.byteLimit
        var total: Int64 = 0
        var count = 0
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(
            at: Self.downloadsDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for url in files {
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values?.isRegularFile == true else { continue }
                total += Int64(values?.fileSize ?? 0)
                count += 1
            }
        }
        let usage = DownloadStorageUsage(usedBytes: total, fileCount: count, limitBytes: limit)
        storageUsage = usage
        return usage
    }

    ///
    /// Eviction policy (AntennaPod-like: prefer deleting played):
    /// 1. While `usedBytes > limit`, delete downloaded episodes marked **played**, oldest file
    ///    modification date first (proxy for “longest since kept / LRU among played”).
    /// 2. If still over limit after all played files are gone, delete **unplayed** downloads
    ///    oldest-mtime-first (LRU among remaining).
    /// 3. Never deletes the episode currently in the catalog mid-write; skips missing files.
    /// 4. Unlimited (`byteLimit == nil`) is a no-op.
    ///
    /// Called after successful downloads, on Settings open, and optionally at app launch.
    @discardableResult
    func enforceStorageLimit(keepEpisodeId: String? = nil) -> Int {
        refreshStorageUsage()
        guard let limit = settings?.downloadStorageLimit.byteLimit else {
            return 0
        }
        var removed = 0
        while storageUsage.usedBytes > limit {
            guard let victim = nextEvictionCandidate(keeping: keepEpisodeId) else {
                break
            }
            let sizeBefore = storageUsage.usedBytes
            delete(victim.episode)
            removed += 1
            // Safety: if delete did not shrink usage, stop to avoid infinite loop.
            if storageUsage.usedBytes >= sizeBefore {
                break
            }
        }
        return removed
    }

    /// App launch / Settings: refresh usage then evict if over byte budget and/or episode-count cache.
    func runStorageMaintenance() {
        refreshStorageUsage()
        _ = enforceStorageLimit()
        _ = enforceEpisodeCacheLimit()
    }

    /// Keeps completed Downloads catalog at or under `downloadEpisodeCacheLimit`.
    /// Eviction order (honest — favorites and queue are never auto-deleted by this cap):
    /// 1. Played + not favorited + not queued, oldest file mtime first.
    /// 2. Unplayed + not favorited + not queued, oldest mtime first.
    /// 3. If only favorites / queued remain over the cap, stop (no silent favorite deletion).
    /// 4. Unlimited (`episodeLimit == nil`) is a no-op.
    /// 5. `keepEpisodeId` (just-finished download) is skipped when choosing victims.
    ///
    /// Distinct from the byte `enforceStorageLimit` (which does not protect favorites/queue).
    /// Called after successful downloads, on Settings open, and on app launch / backup reload.
    @discardableResult
    func enforceEpisodeCacheLimit(keepEpisodeId: String? = nil) -> Int {
        guard let limit = settings?.downloadEpisodeCacheLimit.episodeLimit else {
            return 0
        }
        var removed = 0
        while downloads.count > limit {
            guard let victim = nextEpisodeCacheEvictionCandidate(keeping: keepEpisodeId) else {
                break
            }
            let countBefore = downloads.count
            delete(victim.episode)
            removed += 1
            if downloads.count >= countBefore {
                break
            }
        }
        return removed
    }

    // MARK: - Delegate callbacks (from DownloadSessionDelegate)

    fileprivate func handleMovedDownload(taskIdentifier: Int, fileName: String, episode: PodcastEpisode) {
        let completedAt = Int64(Date().timeIntervalSince1970 * 1000)
        let item = DownloadedEpisode(
            episode: episode,
            fileName: fileName,
            downloadedAtEpochMs: completedAt
        )
        downloads.removeAll { $0.id == item.id }
        downloads.append(item)
        persistCompleted()
        refreshStorageUsage()
        // Keep the episode we just finished; evict older/played peers if over budget.
        _ = enforceStorageLimit(keepEpisodeId: episode.id)
        _ = enforceEpisodeCacheLimit(keepEpisodeId: episode.id)
        // Optional success banner (Settings default off). Foreground + background session finish
        // both land here after a successful temp→Documents move — not on cancel/failure.
        let feedTitle = store.map { $0.displayTitle(containingEpisodeId: episode.id) }
        Task {
            await DownloadCompleteNotificationCoordinator.notifyIfNeeded(
                episode: episode,
                feedTitle: feedTitle,
                settings: settings
            )
        }
    }

    fileprivate func handleTaskCompleted(taskIdentifier: Int, error: Error?) {
        let mapping = pendingByTaskId.removeValue(forKey: taskIdentifier)
        sessionDelegate.removePending(for: taskIdentifier)
        persistPending()
        if let episodeId = mapping?.episode.id {
            inProgress.remove(episodeId)
        }
        if let error, (error as NSError).code != NSURLErrorCancelled {
            // HTTP Basic 401s arrive as a challenge. No matching Keychain password, a
            // rejected password, or a media host that is not the feed host cancels that
            // challenge (NSURLError -1012) before didFinishDownloadingTo can see status 401.
            let message = Self.userFacingTransportFailureMessage(error)
            if let mapping {
                recordFailure(episode: mapping.episode, message: message)
                let destination = Self.downloadsDirectory.appendingPathComponent(mapping.fileName)
                if !downloads.contains(where: { $0.id == mapping.episode.id }) {
                    try? FileManager.default.removeItem(at: destination)
                }
            } else {
                lastError = message
            }
        }
        // Free slot → start next waiting download (if any).
        pumpWaitingQueue()
    }

    fileprivate func handleSessionFinishedEvents() {
        let handler = backgroundCompletionHandler
        backgroundCompletionHandler = nil
        handler?()
    }

    fileprivate func reportError(_ message: String, episode: PodcastEpisode? = nil) {
        if let episode {
            recordFailure(episode: episode, message: message)
        } else {
            lastError = message
        }
    }

    /// Clears the persisted error ring buffer and the banner `lastError`.
    func clearDownloadErrors() {
        recentErrors = []
        lastError = nil
        PodcastPersistence.saveDownloadErrors([])
    }

    /// Episode still in the library with a network-downloadable URL (not local-folder `file://`).
    /// Returns `nil` when the episode was unsubscribed / dropped, has no media URL, or is a
    /// local-folder file (already on disk — no network transfer to retry).
    func episodeForDownloadErrorRetry(
        _ entry: DownloadErrorEntry,
        store: PodcastStore
    ) -> PodcastEpisode? {
        guard let episode = store.episode(id: entry.episodeId) else { return nil }
        guard let raw = episode.downloadUrl, !raw.isEmpty else { return nil }
        guard !LocalFolderFeed.isLocalFileDownloadURL(raw) else { return nil }
        return episode
    }

    /// Whether **Retry** should be enabled for this log row.
    func canRetryDownloadError(_ entry: DownloadErrorEntry, store: PodcastStore) -> Bool {
        guard episodeForDownloadErrorRetry(entry, store: store) != nil else { return false }
        return !inProgress.contains(entry.episodeId)
    }

    /// Removes one persisted error row and refreshes the Downloads banner from the newest
    /// remaining entry (or clears it when the log is empty).
    func removeDownloadError(_ entry: DownloadErrorEntry) {
        let next = recentErrors.filter { $0.id != entry.id }
        recentErrors = next
        lastError = next.first?.message
        PodcastPersistence.saveDownloadErrors(next)
    }

    /// Per-row **Retry**: drops this log entry, then enqueues via the normal manual
    /// `download(_:)` path (Wi‑Fi / cellular gates, storage eviction, background session —
    /// no invented retry queue). A later failure appends a **new** log entry.
    func retryDownloadError(_ entry: DownloadErrorEntry, store: PodcastStore) async {
        guard let episode = episodeForDownloadErrorRetry(entry, store: store) else { return }
        guard !inProgress.contains(episode.id) else { return }
        removeDownloadError(entry)
        await download(episode, source: .manual)
    }

    // MARK: - Error log

    /// Challenge cancellation (-1012 / -1013) is how URLSession reports HTTP Basic 401
    /// when this app does not supply credentials. Show the same authentication hint as a
    /// literal HTTP 401 response (Podcast settings → Authentication), not the system
    /// "connection was cancelled" text.
    private static func userFacingTransportFailureMessage(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .userCancelledAuthentication, .userAuthenticationRequired:
                return FeedHttpBasicAuth.unauthorizedDownloadMessage
            default:
                break
            }
        }
        return error.localizedDescription
    }

    private func recordFailure(episode: PodcastEpisode, message: String) {
        let feedTitle = store?.displayTitle(containingEpisodeId: episode.id) ?? ""
        let entry = DownloadErrorEntry(
            episodeId: episode.id,
            episodeTitle: episode.title,
            feedTitle: feedTitle,
            message: message
        )
        var next = recentErrors
        next.insert(entry, at: 0)
        if next.count > Self.downloadErrorRingCapacity {
            next = Array(next.prefix(Self.downloadErrorRingCapacity))
        }
        recentErrors = next
        lastError = message
        PodcastPersistence.saveDownloadErrors(next)
        Task {
            await DownloadErrorNotificationCoordinator.notifyIfNeeded(
                entry: entry,
                settings: settings
            )
        }
    }

    // MARK: - Eviction helpers

    private func nextEvictionCandidate(keeping keepEpisodeId: String?) -> DownloadedEpisode? {
        let candidates = downloads.filter { item in
            if let keepEpisodeId, item.id == keepEpisodeId { return false }
            return FileManager.default.fileExists(atPath: item.localFileURL.path)
        }
        guard !candidates.isEmpty else { return nil }

        func mtime(_ item: DownloadedEpisode) -> Date {
            let values = try? item.localFileURL.resourceValues(forKeys: [.contentModificationDateKey])
            return values?.contentModificationDate ?? .distantPast
        }

        let played = candidates.filter { store?.isPlayed($0.id) == true }
        if let oldestPlayed = played.min(by: { mtime($0) < mtime($1) }) {
            return oldestPlayed
        }
        return candidates.min(by: { mtime($0) < mtime($1) })
    }

    /// Episode-count cache victim: never favorites or queued; prefer played, then unplayed; oldest mtime.
    private func nextEpisodeCacheEvictionCandidate(keeping keepEpisodeId: String?) -> DownloadedEpisode? {
        let candidates = downloads.filter { item in
            if let keepEpisodeId, item.id == keepEpisodeId { return false }
            guard FileManager.default.fileExists(atPath: item.localFileURL.path) else { return false }
            // Never auto-delete favorited / starred offline files via the count cache.
            if store?.isFavorite(item.id) == true { return false }
            // Never auto-delete queued episodes via the count cache (user still intends to listen).
            if store?.isInQueue(item.id) == true { return false }
            return true
        }
        guard !candidates.isEmpty else { return nil }

        func mtime(_ item: DownloadedEpisode) -> Date {
            let values = try? item.localFileURL.resourceValues(forKeys: [.contentModificationDateKey])
            return values?.contentModificationDate ?? .distantPast
        }

        let played = candidates.filter { store?.isPlayed($0.id) == true }
        if let oldestPlayed = played.min(by: { mtime($0) < mtime($1) }) {
            return oldestPlayed
        }
        return candidates.min(by: { mtime($0) < mtime($1) })
    }

    // MARK: - Persistence / relaunch

    private func reloadFromDisk() {
        let catalog = PodcastPersistence.loadDownloadedEpisodes()
        var next = catalog.filter {
            FileManager.default.fileExists(atPath: $0.localFileURL.path)
        }
        // Older catalogs lack `downloadedAtEpochMs`; backfill once from file dates when possible.
        var backfilled = false
        for i in next.indices where next[i].downloadedAtEpochMs == nil {
            if let proxy = next[i].fileDownloadProxyEpochMs() {
                next[i].downloadedAtEpochMs = proxy
                backfilled = true
            }
        }
        downloads = next
        if downloads.count != catalog.count || backfilled {
            persistCompleted()
        }

        let pending = PodcastPersistence.loadPendingDownloads()
        pendingByTaskId = Dictionary(uniqueKeysWithValues: pending.map { ($0.taskIdentifier, $0) })
        for (id, mapping) in pendingByTaskId {
            sessionDelegate.setPending(mapping, for: id)
        }
        inProgress = Set(pending.map(\.episode.id))
    }

    /// After backup import: prune catalog to media files present on this device
    /// (media may have been restored from ZIP `downloads/` when the backup included them).
    /// Clears in-flight pending map (not restored across backup). Refreshes storage usage.
    func reloadAfterBackupImport() {
        // Drop stale pending mappings from before restore.
        pendingByTaskId.removeAll()
        waitingQueue.removeAll()
        inProgress.removeAll()
        sessionDelegate.removeAllPending()
        PodcastPersistence.savePendingDownloads([])
        reloadFromDisk()
        recentErrors = PodcastPersistence.loadDownloadErrors()
        lastError = nil
        runStorageMaintenance()
    }

    private func reconnectOutstandingTasks() {
        session.getTasksWithCompletionHandler { [weak self] _, _, downloadTasks in
            Task { @MainActor in
                guard let self else { return }
                let liveIds = Set(downloadTasks.map(\.taskIdentifier))
                let stale = self.pendingByTaskId.keys.filter { !liveIds.contains($0) }
                for id in stale {
                    if let mapping = self.pendingByTaskId.removeValue(forKey: id) {
                        self.sessionDelegate.removePending(for: id)
                        self.inProgress.remove(mapping.episode.id)
                    }
                }
                for task in downloadTasks {
                    if let mapping = self.pendingByTaskId[task.taskIdentifier] {
                        self.inProgress.insert(mapping.episode.id)
                    }
                }
                self.persistPending()
            }
        }
    }

    private func persistCompleted() {
        PodcastPersistence.saveDownloadedEpisodes(downloads)
    }

    private func persistPending() {
        PodcastPersistence.savePendingDownloads(Array(pendingByTaskId.values))
    }

    private func cancelTask(for episodeId: String) {
        // Waiting (not yet a URLSession task): drop from FIFO only.
        if let idx = waitingQueue.firstIndex(where: { $0.episode.id == episodeId }) {
            waitingQueue.remove(at: idx)
            inProgress.remove(episodeId)
            return
        }
        let taskIds = pendingByTaskId.filter { $0.value.episode.id == episodeId }.map(\.key)
        guard !taskIds.isEmpty else {
            inProgress.remove(episodeId)
            return
        }
        session.getTasksWithCompletionHandler { _, _, downloadTasks in
            for task in downloadTasks where taskIds.contains(task.taskIdentifier) {
                task.cancel()
            }
        }
        for id in taskIds {
            pendingByTaskId.removeValue(forKey: id)
            sessionDelegate.removePending(for: id)
        }
        persistPending()
        inProgress.remove(episodeId)
        // Free slot → start next waiting download (if any).
        pumpWaitingQueue()
    }
}

// MARK: - URLSessionDownloadDelegate

/// Holds a lock-protected pending map so `didFinishDownloadingTo` can move the temp file
/// synchronously (required by URLSession) before returning.
final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate {
    weak var owner: DownloadService?

    private let lock = NSLock()
    private var pendingByTaskId: [Int: PendingDownloadMapping] = [:]

    func setPending(_ mapping: PendingDownloadMapping, for taskIdentifier: Int) {
        lock.lock()
        pendingByTaskId[taskIdentifier] = mapping
        lock.unlock()
    }

    func removePending(for taskIdentifier: Int) {
        lock.lock()
        pendingByTaskId.removeValue(forKey: taskIdentifier)
        lock.unlock()
    }

    func removeAllPending() {
        lock.lock()
        pendingByTaskId.removeAll()
        lock.unlock()
    }

    private func pending(for taskIdentifier: Int) -> PendingDownloadMapping? {
        lock.lock()
        defer { lock.unlock() }
        return pendingByTaskId[taskIdentifier]
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let taskId = downloadTask.taskIdentifier
        guard let mapping = pending(for: taskId) else {
            return
        }
        if let http = downloadTask.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            Task { @MainActor in
                let message: String
                if http.statusCode == 401 {
                    message = FeedHttpBasicAuth.unauthorizedDownloadMessage
                } else {
                    message = String(localized: "Download failed (HTTP \(http.statusCode))")
                }
                self.owner?.reportError(
                    message,
                    episode: mapping.episode
                )
            }
            return
        }
        let destination = DownloadService.downloadsDirectory.appendingPathComponent(mapping.fileName)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            Task { @MainActor in
                self.owner?.handleMovedDownload(
                    taskIdentifier: taskId,
                    fileName: mapping.fileName,
                    episode: mapping.episode
                )
            }
        } catch {
            Task { @MainActor in
                self.owner?.reportError(error.localizedDescription, episode: mapping.episode)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let taskId = task.taskIdentifier
        Task { @MainActor in
            self.owner?.handleTaskCompleted(taskIdentifier: taskId, error: error)
        }
    }

    /// HTTP Basic challenge: proxy credentials from `AppHTTPProxy` Keychain when
    /// `protectionSpace.isProxy`; otherwise per-feed Keychain for the pending episode’s feed
    /// when the challenge host matches the feed host. Never logs the password.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let method = challenge.protectionSpace.authenticationMethod
        guard method == NSURLAuthenticationMethodHTTPBasic
            || method == NSURLAuthenticationMethodDefault
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        // Avoid retry loops after a failed Basic attempt.
        if challenge.previousFailureCount > 0 {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        // Authenticated HTTP(S) proxy (optional username/password).
        if challenge.protectionSpace.isProxy {
            guard let proxy = AppHTTPProxy.resolved(), proxy.hasCredentials else {
                completionHandler(.performDefaultHandling, nil)
                return
            }
            let credential = URLCredential(
                user: proxy.username,
                password: proxy.password,
                persistence: .forSession
            )
            completionHandler(.useCredential, credential)
            return
        }
        guard let mapping = pending(for: task.taskIdentifier) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let challengeHost = challenge.protectionSpace.host.lowercased()
        // Keychain is thread-safe; feedId on the mapping is not a secret (password never persisted here).
        let feedId = mapping.feedId
            ?? owner?.store?.feed(containingEpisodeId: mapping.episode.id)?.id
        let creds: FeedHttpBasicCredentials? = {
            guard let feedId,
                  let c = FeedHttpBasicAuthKeychain.load(for: feedId),
                  c.isUsable
            else {
                return nil
            }
            // Prefer matching challenge host to the media URL host (same-host policy).
            if let media = mapping.episode.downloadUrl, let mediaURL = URL(string: media),
               let mediaHost = mediaURL.host?.lowercased(),
               mediaHost != challengeHost {
                return nil
            }
            return c
        }()
        guard let creds else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        let credential = URLCredential(
            user: creds.trimmedUsername,
            password: creds.password,
            persistence: .forSession
        )
        completionHandler(.useCredential, credential)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            self.owner?.handleSessionFinishedEvents()
        }
    }
}
