import Foundation

/// Synthetic podcast feeds backed by a user-picked folder (security-scoped bookmark).
/// No RSS / no network — episodes are audio files in the folder (non-recursive).
/// Podcasting 2.0 / iTunes RSS tags do not apply; omitted from OPML/HTML/gpodder.
enum LocalFolderFeed {
    static let urlScheme = "local-folder"

    /// Audio extensions treated as episodes (lowercase, no dot).
    static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "flac"]

    static func feedURL(for id: UUID) -> String {
        "\(urlScheme)://\(id.uuidString.lowercased())"
    }

    static func isLocalFolderFeedURL(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            return false
        }
        return scheme == urlScheme
    }

    static func isLocalFolderFeed(_ feed: PodcastFeed) -> Bool {
        isLocalFolderFeedURL(feed.feedUrl)
    }

    /// Formats accepted as episodes (display / VoiceOver).
    static var audioFormatsDisplay: String {
        "mp3, m4a, aac, wav, flac"
    }

    /// Whether a media URL is an already-local `file://` path (folder episode).
    static func isLocalFileDownloadURL(_ raw: String?) -> Bool {
        guard let raw, let url = URL(string: raw) else { return false }
        return url.isFileURL
    }

    /// Stable episode id for a relative path inside a local-folder feed.
    static func episodeId(feedId: UUID, relativePath: String) -> String {
        "local-folder:\(feedId.uuidString.lowercased()):\(relativePath)"
    }

    static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/mp4"
        case "aac": return "audio/aac"
        case "wav": return "audio/wav"
        case "flac": return "audio/flac"
        default: return "audio/\(ext.lowercased())"
        }
    }
}

enum LocalFolderFeedError: LocalizedError {
    case cannotAccessFolder
    case bookmarkFailed
    case bookmarkStale
    case notAFolder
    case alreadySubscribed

    var errorDescription: String? {
        switch self {
        case .cannotAccessFolder:
            return String(localized: "Could not access the selected folder. Pick it again under Add podcast → Folder. If Files permission was revoked, choose the folder again.")
        case .bookmarkFailed:
            return String(localized: "Could not save lasting access to this folder. Try another folder from Files.")
        case .bookmarkStale:
            return String(localized: "Folder access expired or was revoked. Unsubscribe this local folder feed, then add the folder again under Add podcast → Folder.")
        case .notAFolder:
            return String(localized: "Please choose a folder, not a single file.")
        case .alreadySubscribed:
            return String(localized: "This folder is already added as a local folder feed.")
        }
    }
}

/// Persists security-scoped bookmarks for local folder feeds (`local-folder-bookmarks.json`).
@MainActor
enum LocalFolderBookmarkStore {
    /// feed UUID string → base64 bookmark data
    private static var cache: [String: String]?

    private static func loadMap() -> [String: String] {
        if let cache { return cache }
        let map = PodcastPersistence.loadLocalFolderBookmarks()
        cache = map
        return map
    }

    private static func saveMap(_ map: [String: String]) {
        cache = map
        PodcastPersistence.saveLocalFolderBookmarks(map)
    }

    static func reloadFromPersistence() {
        cache = PodcastPersistence.loadLocalFolderBookmarks()
    }

    /// Create a security-scoped bookmark for a user-picked folder URL (call while scoped access is active).
    static func saveBookmark(forFolderURL url: URL, feedId: UUID) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw LocalFolderFeedError.notAFolder
        }
        do {
            // iOS: document-picker URLs yield security-scoped bookmarks via `.minimalBookmark`.
            let data = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            var map = loadMap()
            map[feedId.uuidString.lowercased()] = data.base64EncodedString()
            saveMap(map)
        } catch {
            throw LocalFolderFeedError.bookmarkFailed
        }
    }

    static func release(feedId: UUID) {
        var map = loadMap()
        map.removeValue(forKey: feedId.uuidString.lowercased())
        saveMap(map)
        LocalFolderAccess.endAccess(feedId: feedId)
    }

    /// Resolve bookmark to a folder URL (does not start access).
    static func resolveFolderURL(feedId: UUID) throws -> URL {
        let map = loadMap()
        guard let b64 = map[feedId.uuidString.lowercased()],
              let data = Data(base64Encoded: b64) else {
            throw LocalFolderFeedError.bookmarkStale
        }
        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: data,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            throw LocalFolderFeedError.bookmarkStale
        }
        if isStale {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            if accessed {
                try? saveBookmark(forFolderURL: url, feedId: feedId)
            } else {
                throw LocalFolderFeedError.bookmarkStale
            }
        }
        return url
    }

    static func hasBookmark(feedId: UUID) -> Bool {
        loadMap()[feedId.uuidString.lowercased()] != nil
    }

    /// Find an existing local-folder subscription that points at the same folder path.
    static func existingFeed(matchingFolderURL url: URL, in feeds: [PodcastFeed]) -> PodcastFeed? {
        let path = url.standardizedFileURL.path
        for feed in feeds where LocalFolderFeed.isLocalFolderFeed(feed) {
            guard let resolved = try? resolveFolderURL(feedId: feed.id) else { continue }
            if resolved.standardizedFileURL.path == path {
                return feed
            }
        }
        return nil
    }
}

/// Tracks started security-scoped access so playback / refresh can read folder files.
@MainActor
enum LocalFolderAccess {
    private static var active: [UUID: URL] = [:]

    /// Resolve bookmark, start access if needed, return folder URL.
    @discardableResult
    static func beginAccess(feedId: UUID) throws -> URL {
        if let existing = active[feedId] {
            return existing
        }
        let url = try LocalFolderBookmarkStore.resolveFolderURL(feedId: feedId)
        guard url.startAccessingSecurityScopedResource() else {
            throw LocalFolderFeedError.cannotAccessFolder
        }
        active[feedId] = url
        return url
    }

    static func endAccess(feedId: UUID) {
        if let url = active.removeValue(forKey: feedId) {
            url.stopAccessingSecurityScopedResource()
        }
    }

    /// Ensure access for a `file://` episode that belongs to a local-folder feed.
    static func ensureAccessForEpisodeFileURL(_ fileURL: URL, feeds: [PodcastFeed]) {
        guard fileURL.isFileURL else { return }
        for feed in feeds where LocalFolderFeed.isLocalFolderFeed(feed) {
            if feed.episodes.contains(where: { ep in
                guard let s = ep.downloadUrl, let u = URL(string: s) else { return false }
                return u.standardizedFileURL.path == fileURL.standardizedFileURL.path
            }) {
                _ = try? beginAccess(feedId: feed.id)
                return
            }
        }
    }
}

/// Scan a folder and build a synthetic `PodcastFeed`.
enum LocalFolderScanner {
    /// Non-recursive listing of audio files in `folderURL` (must already be accessible).
    static func buildFeed(
        feedId: UUID,
        folderURL: URL,
        existingTitle: String? = nil
    ) throws -> PodcastFeed {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw LocalFolderFeedError.notAFolder
        }

        let trimmedExisting = existingTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = trimmedExisting.isEmpty ? folderURL.lastPathComponent : trimmedExisting

        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw LocalFolderFeedError.cannotAccessFolder
        }

        var episodes: [PodcastEpisode] = []
        for fileURL in contents {
            let values = try? fileURL.resourceValues(forKeys: [
                .isRegularFileKey, .contentModificationDateKey, .fileSizeKey
            ])
            guard values?.isRegularFile == true else { continue }
            let ext = fileURL.pathExtension.lowercased()
            guard LocalFolderFeed.audioExtensions.contains(ext) else { continue }

            let relative = fileURL.lastPathComponent
            let nameTitle = fileURL.deletingPathExtension().lastPathComponent
            let mtime = values?.contentModificationDate ?? Date()
            let size = Int64(values?.fileSize ?? 0)

            episodes.append(
                PodcastEpisode(
                    id: LocalFolderFeed.episodeId(feedId: feedId, relativePath: relative),
                    title: nameTitle,
                    link: nil,
                    pubDateEpochMs: Int64(mtime.timeIntervalSince1970 * 1000),
                    downloadUrl: fileURL.absoluteString,
                    mimeType: LocalFolderFeed.mimeType(forExtension: ext),
                    size: size,
                    transcriptUrl: nil,
                    transcriptType: nil,
                    chapters: [],
                    podcastIndexChapterUrl: nil
                )
            )
        }

        episodes.sort { lhs, rhs in
            let l = lhs.pubDateEpochMs ?? Int64.min
            let r = rhs.pubDateEpochMs ?? Int64.min
            if l != r { return l > r }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        return PodcastFeed(
            id: feedId,
            title: title,
            feedUrl: LocalFolderFeed.feedURL(for: feedId),
            siteLink: nil,
            imageUrl: nil,
            descriptionText: String(
                localized: "Local folder · \(folderURL.lastPathComponent) · no RSS · refresh re-scans files · Podcasting 2.0 tags do not apply · omitted from OPML"
            ),
            author: nil,
            language: nil,
            fundingUrl: nil,
            fundingLabel: nil,
            categories: [],
            isLocked: false,
            lockedOwner: nil,
            podcastGuid: nil,
            episodes: episodes
        )
    }
}
