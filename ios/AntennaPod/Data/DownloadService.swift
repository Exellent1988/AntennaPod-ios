import Foundation

struct DownloadedEpisode: Identifiable, Hashable, Codable {
    let episode: PodcastEpisode
    /// File name under `DownloadService.downloadsDirectory` (not an absolute path).
    let fileName: String

    var id: String { episode.id }

    var localFileURL: URL {
        DownloadService.downloadsDirectory.appendingPathComponent(fileName)
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
        guard let item = downloads.first(where: { $0.id == episode.id }) else { return nil }
        let url = item.localFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    func isDownloaded(_ episode: PodcastEpisode) -> Bool {
        localURL(for: episode) != nil
    }

    /// Starts a background `URLSession` download task. Continues while the app is suspended
    /// (system-permitting); mapping is persisted for relaunch.
    func download(_ episode: PodcastEpisode) async {
        guard let remote = episode.downloadUrl, let url = URL(string: remote) else {
            recordFailure(episode: episode, message: "Episode has no media URL")
            return
        }
        if inProgress.contains(episode.id) {
            return
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

    /// Deletes every completed download (confirmation is UI responsibility). Cancels in-flight tasks.
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
        let item = DownloadedEpisode(episode: episode, fileName: fileName)
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
        downloads = catalog.filter {
            FileManager.default.fileExists(atPath: $0.localFileURL.path)
        }
        if downloads.count != catalog.count {
            persistCompleted()
        }

        let pending = PodcastPersistence.loadPendingDownloads()
        pendingByTaskId = Dictionary(uniqueKeysWithValues: pending.map { ($0.taskIdentifier, $0) })
        for (id, mapping) in pendingByTaskId {
            sessionDelegate.setPending(mapping, for: id)
        }
        inProgress = Set(pending.map(\.episode.id))
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
