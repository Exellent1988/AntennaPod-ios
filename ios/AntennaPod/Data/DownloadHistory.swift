import Foundation

/// One finished download attempt, success or failure. Android: DownloadResult rows in the
/// DownloadLog table (storage/database/.../DBWriter.addDownloadStatus, DownloadLogFragment), which
/// keeps successes and failures with date and reason. Persisted as download-history.json.
struct DownloadHistoryEntry: Identifiable, Hashable, Codable {
    let id: UUID
    let episodeId: String
    let episodeTitle: String
    let feedTitle: String
    let succeeded: Bool
    /// Failure reason; nil on success.
    let message: String?
    let byteSize: Int64?
    let timestampEpochMs: Int64

    init(
        id: UUID = UUID(),
        episodeId: String,
        episodeTitle: String,
        feedTitle: String,
        succeeded: Bool,
        message: String? = nil,
        byteSize: Int64? = nil,
        timestampEpochMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.id = id
        self.episodeId = episodeId
        self.episodeTitle = episodeTitle
        self.feedTitle = feedTitle
        self.succeeded = succeeded
        self.message = message
        self.byteSize = byteSize
        self.timestampEpochMs = timestampEpochMs
    }
}

enum DownloadHistoryLog {
    /// Android prunes DownloadLog to the newest entries too (DBWriter / cleanup); we keep 500.
    static let capacity = 500

    /// Newest first, capped at `capacity`.
    static func appending(_ entry: DownloadHistoryEntry, to list: [DownloadHistoryEntry]) -> [DownloadHistoryEntry] {
        var next = list
        next.insert(entry, at: 0)
        if next.count > capacity { next = Array(next.prefix(capacity)) }
        return next
    }

    private static var url: URL {
        PodcastPersistence.applicationSupportDirectory.appendingPathComponent("download-history.json")
    }

    static func load(from fileURL: URL? = nil) -> [DownloadHistoryEntry] {
        guard let data = try? Data(contentsOf: fileURL ?? url) else { return [] }
        return (try? JSONDecoder().decode([DownloadHistoryEntry].self, from: data)) ?? []
    }

    static func save(_ items: [DownloadHistoryEntry], to fileURL: URL? = nil) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL ?? url, options: .atomic)
    }
}
