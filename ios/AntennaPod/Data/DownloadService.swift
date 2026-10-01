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
            lastError = "Episode has no media URL"
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
    }

    // MARK: - Delegate callbacks (from DownloadSessionDelegate)

    fileprivate func handleMovedDownload(taskIdentifier: Int, fileName: String, episode: PodcastEpisode) {
        let item = DownloadedEpisode(episode: episode, fileName: fileName)
        downloads.removeAll { $0.id == item.id }
        downloads.append(item)
        persistCompleted()
    }

    fileprivate func handleTaskCompleted(taskIdentifier: Int, error: Error?) {
        let mapping = pendingByTaskId.removeValue(forKey: taskIdentifier)
        sessionDelegate.removePending(for: taskIdentifier)
        persistPending()
        if let episodeId = mapping?.episode.id {
            inProgress.remove(episodeId)
        }
        if let error, (error as NSError).code != NSURLErrorCancelled {
            lastError = error.localizedDescription
            if let mapping {
                let destination = Self.downloadsDirectory.appendingPathComponent(mapping.fileName)
                if !downloads.contains(where: { $0.id == mapping.episode.id }) {
                    try? FileManager.default.removeItem(at: destination)
                }
            }
        }
    }

    fileprivate func handleSessionFinishedEvents() {
        let handler = backgroundCompletionHandler
        backgroundCompletionHandler = nil
        handler?()
    }

    fileprivate func reportError(_ message: String) {
        lastError = message
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
                self.owner?.reportError("Download failed (HTTP \(http.statusCode))")
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
                self.owner?.reportError(error.localizedDescription)
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
