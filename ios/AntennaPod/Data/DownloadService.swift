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
struct PendingDownloadMapping: Codable, Hashable {
    var taskIdentifier: Int
    var episode: PodcastEpisode
    var fileName: String
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

    /// Bound from the app so eviction can prefer played episodes (AntennaPod-like).
    weak var store: PodcastStore?
    /// Bound for the configured byte budget.
    weak var settings: AppSettings?

    private let sessionDelegate = DownloadSessionDelegate()
    private var session: URLSession!
    /// Live task id → episode (+ destination file name).
    private var pendingByTaskId: [Int: PendingDownloadMapping] = [:]
    private var backgroundCompletionHandler: (() -> Void)?

    private static weak var activeInstance: DownloadService?
    private static var pendingBackgroundCompletionHandler: (() -> Void)?

    init() {
        let config = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.allowsCellularAccess = true
        session = URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
        sessionDelegate.owner = self

        Self.activeInstance = self
        if let pending = Self.pendingBackgroundCompletionHandler {
            backgroundCompletionHandler = pending
            Self.pendingBackgroundCompletionHandler = nil
        }

        reloadFromDisk()
        reconnectOutstandingTasks()
        refreshStorageUsage()
        recentErrors = PodcastPersistence.loadDownloadErrors()
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

    static let manualCellularBlockedMessage =
        "Manual downloads are Wi‑Fi only. Connect to Wi‑Fi or Ethernet, or turn off Manual download Wi‑Fi only in Settings → Network / Downloads."

    /// Soft cap for Feed detail **Download all** (newest eligible first).
    static let feedDownloadAllCap = 50

    /// Episodes on `feed` eligible for manual bulk download: unplayed, not archived,
    /// not already downloaded / in-flight, with a remote media URL (skips local-folder files).
    /// Newest `pubDateEpochMs` first, limited to `cap` (default `feedDownloadAllCap`).
    func eligibleForFeedDownloadAll(
        in feed: PodcastFeed,
        store: PodcastStore,
        cap: Int = DownloadService.feedDownloadAllCap
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
            guard let raw = episode.downloadUrl, !raw.isEmpty else { continue }
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

    /// Starts a background `URLSession` download task. Continues while the app is suspended
    /// (system-permitting); mapping is persisted for relaunch.
    /// - Parameter source: `.manual` (default) honors `manualDownloadWifiOnly`; `.automatic`
    ///   skips that gate (auto-download uses `autoDownloadWifiOnly` in `AutoDownloadCoordinator`).
    func download(_ episode: PodcastEpisode, source: DownloadEnqueueSource = .manual) async {
        guard let remote = episode.downloadUrl, let url = URL(string: remote) else {
            recordFailure(episode: episode, message: "Episode has no media URL")
            return
        }
        // Already-local folder files — treat as present; do not start a network transfer.
        if url.isFileURL {
            if FileManager.default.fileExists(atPath: url.path) {
                lastError = nil
            } else {
                recordFailure(episode: episode, message: "Local file missing")
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

        let ext = url.pathExtension.isEmpty ? "mp3" : url.pathExtension
        let safeName = episode.id
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
        let fileName = "\(safeName).\(ext)"

        let task = session.downloadTask(with: url)
        let mapping = PendingDownloadMapping(
            taskIdentifier: task.taskIdentifier,
            episode: episode,
            fileName: fileName
        )
        pendingByTaskId[task.taskIdentifier] = mapping
        sessionDelegate.setPending(mapping, for: task.taskIdentifier)
        persistPending()
        task.resume()
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

    /// Approximate total byte size of files that `clearAllDownloads` would remove (full completed catalog).
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
    /// Cancels in-flight tasks for catalog episode ids. Confirmation is UI responsibility.
    func clearAllDownloads() {
        let episodeIds = downloads.map(\.id)
        for id in episodeIds {
            cancelTask(for: id)
        }
        for item in downloads {
            try? FileManager.default.removeItem(at: item.localFileURL)
        }
        downloads.removeAll()
        persistCompleted()
        refreshStorageUsage()
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

    /// App launch / Settings: refresh usage then evict if over budget.
    func runStorageMaintenance() {
        refreshStorageUsage()
        _ = enforceStorageLimit()
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
    }

    fileprivate func handleTaskCompleted(taskIdentifier: Int, error: Error?) {
        let mapping = pendingByTaskId.removeValue(forKey: taskIdentifier)
        sessionDelegate.removePending(for: taskIdentifier)
        persistPending()
        if let episodeId = mapping?.episode.id {
            inProgress.remove(episodeId)
        }
        if let error, (error as NSError).code != NSURLErrorCancelled {
            if let mapping {
                recordFailure(episode: mapping.episode, message: error.localizedDescription)
                let destination = Self.downloadsDirectory.appendingPathComponent(mapping.fileName)
                if !downloads.contains(where: { $0.id == mapping.episode.id }) {
                    try? FileManager.default.removeItem(at: destination)
                }
            } else {
                lastError = error.localizedDescription
            }
        }
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

    // MARK: - Error log

    private func recordFailure(episode: PodcastEpisode, message: String) {
        let feedTitle = store?.feed(containingEpisodeId: episode.id)?.title ?? ""
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
        let taskIds = pendingByTaskId.filter { $0.value.episode.id == episodeId }.map(\.key)
        guard !taskIds.isEmpty else { return }
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
                self.owner?.reportError(
                    "Download failed (HTTP \(http.statusCode))",
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

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            self.owner?.handleSessionFinishedEvents()
        }
    }
}
