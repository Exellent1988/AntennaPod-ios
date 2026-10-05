import Foundation

/// Manifest for an AntennaPod **iOS** JSON backup (not Android DB).
struct DataBackupManifest: Codable, Equatable {
    static let formatID = "antennapod-ios-json-backup"
    static let currentVersion = 1

    var format: String
    var version: Int
    var createdAtISO8601: String
    var includesMedia: Bool
    var includesKeychainSecrets: Bool
    var files: [String]
    var notes: [String]

    static func make(
        files: [String],
        includesMedia: Bool,
        createdAt: Date = Date()
    ) -> DataBackupManifest {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var notes = [
            "iOS Application Support JSON backup — not AntennaPod Android database export.",
            "Keychain secrets are NOT included (gpodder password, Podcast Index API key/secret, Parental controls PIN). Re-enter passwords/keys after import on a new device.",
            "pending-downloads.json (in-flight tasks) is omitted.",
            "HTML subscription export is separate (Settings → Import / Export), not part of this ZIP.",
            "local-folder-bookmarks.json is included when present; security-scoped bookmarks may not work on another device — re-pick folders after import."
        ]
        if includesMedia {
            notes.insert(
                "Downloads: catalog (downloads.json) plus offline media under ZIP folder downloads/ (Documents/downloads). Large / slow; STORE ZIP (no compression).",
                at: 1
            )
        } else {
            notes.insert(
                "Downloads: catalog metadata only (downloads.json); media under Documents/downloads is not included — re-download offline files, or re-export with Include downloaded episode files.",
                at: 1
            )
        }
        return DataBackupManifest(
            format: formatID,
            version: currentVersion,
            createdAtISO8601: formatter.string(from: createdAt),
            includesMedia: includesMedia,
            includesKeychainSecrets: false,
            files: files.sorted(),
            notes: notes
        )
    }
}

enum DataBackupError: LocalizedError {
    case missingManifest
    case unsupportedFormat(String)
    case unsupportedVersion(Int)
    case noPersistenceFiles
    case encodeFailed
    case importFailed(String)
    case mediaTooLarge(String)

    var errorDescription: String? {
        switch self {
        case .missingManifest:
            return String(localized: "Backup is missing manifest.json")
        case .unsupportedFormat(let f):
            return String(localized: "Unsupported backup format “\(f)” (need \(DataBackupManifest.formatID))")
        case .unsupportedVersion(let v):
            return String(localized: "Unsupported backup version \(v)")
        case .noPersistenceFiles:
            return String(localized: "Backup contains no recognizable persistence files")
        case .encodeFailed:
            return String(localized: "Could not encode backup payload")
        case .importFailed(let msg):
            return msg
        case .mediaTooLarge(let msg):
            return msg
        }
    }
}

/// Export / import of local iOS JSON persistence (+ AppSettings + gpodder prefs; optional Documents/downloads media; no Keychain).
enum DataBackupService {
    static let manifestFileName = "manifest.json"
    static let appSettingsFileName = "app-settings.json"
    static let gpodderPrefsFileName = "gpodder-prefs.json"
    /// ZIP folder for offline episode files (maps to Documents/downloads).
    static let mediaZipFolder = "downloads"

    /// Application Support JSON files included in MVP backup (catalog only for downloads unless media opted in).
    static let persistenceFileNames: [String] = [
        "feeds.json",
        "queue.json",
        "playback.json",
        "downloads.json",
        "feed-settings.json",
        "favorites.json",
        "archived.json",
        "feed-tags.json",
        "download-errors.json",
        "local-folder-bookmarks.json",
        "bookmarks.json",
        "episode-notes.json"
    ]

    // MARK: - Media size estimate (UI warnings)

    /// Count and byte size of files currently under Documents/downloads (for export warnings).
    static func estimateMediaPayload() -> (fileCount: Int, bytes: Int64) {
        let dir = DownloadService.downloadsDirectory
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return (0, 0)
        }
        var count = 0
        var bytes: Int64 = 0
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            count += 1
            bytes += Int64(values?.fileSize ?? 0)
        }
        return (count, bytes)
    }

    static func formatBytes(_ bytes: Int64) -> String {
        DownloadStorageUsage.formatBytes(bytes)
    }

    // MARK: - Export

    /// Build a STORE-compressed ZIP in a temporary directory and return its file URL for the share sheet.
    /// - Parameter includeMedia: when true, add Documents/downloads files under ZIP `downloads/`.
    @MainActor
    static func exportTemporaryZip(
        settings: AppSettings,
        gpodder: GpodderSyncService,
        includeMedia: Bool = false
    ) throws -> URL {
        var entries: [(name: String, data: Data)] = []

        for name in persistenceFileNames {
            let url = PodcastPersistence.fileURL(name)
            if let data = try? Data(contentsOf: url), !data.isEmpty {
                entries.append((name, data))
            } else {
                // Always include empty JSON defaults so import is predictable.
                let empty: Data
                switch name {
                case "feeds.json", "queue.json", "downloads.json", "download-errors.json":
                    empty = Data("[]".utf8)
                default:
                    empty = Data("{}".utf8)
                }
                entries.append((name, empty))
            }
        }

        let settingsData = try encodeJSON(settings.backupSnapshot())
        entries.append((appSettingsFileName, settingsData))

        let gpodderData = try encodeJSON(gpodder.backupSnapshot())
        entries.append((gpodderPrefsFileName, gpodderData))

        if includeMedia {
            let mediaEntries = try collectMediaEntries()
            entries.append(contentsOf: mediaEntries)
        }

        let fileList = entries.map(\.name) + [manifestFileName]
        let manifest = DataBackupManifest.make(files: fileList, includesMedia: includeMedia)
        let manifestData = try encodeJSON(manifest)
        entries.insert((manifestFileName, manifestData), at: 0)

        // ZIP32 STORE: offsets/sizes are UInt32 — reject payloads that cannot fit.
        let totalBytes = entries.reduce(Int64(0)) { $0 + Int64($1.data.count) }
        if totalBytes > Int64(UInt32.max) - 1_048_576 {
            throw DataBackupError.mediaTooLarge(
                String(localized: "Backup payload is too large for a single ZIP (\(Self.formatBytes(totalBytes))). Turn off Include downloaded episode files or free space / fewer downloads.")
            )
        }

        let stamp = Self.fileStamp(Date())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AntennaPod-iOS-Backup-\(stamp).zip", isDirectory: false)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try MinimalZip.writeStoreArchive(entries: entries, to: url)
        return url
    }

    /// Read regular files from Documents/downloads into ZIP entries under `downloads/<fileName>`.
    private static func collectMediaEntries() throws -> [(name: String, data: Data)] {
        let dir = DownloadService.downloadsDirectory
        let urls = try FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        var result: [(name: String, data: Data)] = []
        for fileURL in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            let name = fileURL.lastPathComponent
            guard isSafeMediaFileName(name) else { continue }
            let size = Int64(values?.fileSize ?? 0)
            if size > Int64(UInt32.max) {
                throw DataBackupError.mediaTooLarge(
                    String(localized: "Episode file “\(name)” exceeds ZIP size limits (\(Self.formatBytes(size))).")
                )
            }
            let data = try Data(contentsOf: fileURL)
            result.append(("\(mediaZipFolder)/\(name)", data))
        }
        return result
    }

    // MARK: - Import

    /// Replace persistence + prefs from a backup ZIP. Caller must confirm replace first.
    /// Media entries under `downloads/` are merged onto disk (overwrite same names; do not wipe unrelated local files).
    @MainActor
    static func importZip(
        from url: URL,
        store: PodcastStore,
        settings: AppSettings,
        downloads: DownloadService,
        gpodder: GpodderSyncService
    ) throws {
        let entries = try MinimalZip.readArchive(from: url)
        try applyEntries(
            entries,
            store: store,
            settings: settings,
            downloads: downloads,
            gpodder: gpodder
        )
    }

    @MainActor
    private static func applyEntries(
        _ entries: [String: Data],
        store: PodcastStore,
        settings: AppSettings,
        downloads: DownloadService,
        gpodder: GpodderSyncService
    ) throws {
        guard let manifestData = entries[manifestFileName]
            ?? entries.first(where: { $0.key.hasSuffix("/\(manifestFileName)") })?.value
        else {
            throw DataBackupError.missingManifest
        }
        let manifest = try JSONDecoder().decode(DataBackupManifest.self, from: manifestData)
        guard manifest.format == DataBackupManifest.formatID else {
            throw DataBackupError.unsupportedFormat(manifest.format)
        }
        guard manifest.version >= 1, manifest.version <= DataBackupManifest.currentVersion else {
            throw DataBackupError.unsupportedVersion(manifest.version)
        }

        func data(for fileName: String) -> Data? {
            if let d = entries[fileName] { return d }
            return entries.first(where: { $0.key.hasSuffix("/\(fileName)") })?.value
        }

        // Decode settings first: a truncated or corrupt app-settings.json / gpodder-prefs.json
        // must fail the import before any data file is replaced.
        let settingsSnapshot = try data(for: appSettingsFileName).map {
            try JSONDecoder().decode(AppSettingsBackupSnapshot.self, from: $0)
        }
        let gpodderSnapshot = try data(for: gpodderPrefsFileName).map {
            try JSONDecoder().decode(GpodderBackupSnapshot.self, from: $0)
        }

        var wrotePersistence = false
        for name in persistenceFileNames {
            guard let payload = data(for: name) else { continue }
            try PodcastPersistence.writeFile(name: name, data: payload)
            wrotePersistence = true
        }
        // Clear in-flight download map — not meaningful across restore.
        PodcastPersistence.savePendingDownloads([])

        if let settingsSnapshot {
            settings.applyBackupSnapshot(settingsSnapshot)
        }

        if let gpodderSnapshot {
            gpodder.applyBackupSnapshot(gpodderSnapshot)
        }

        // Optional media: write ZIP downloads/* into Documents/downloads (merge: overwrite, never wipe folder).
        let restoredMediaCount = try restoreMediaFiles(from: entries)

        guard wrotePersistence
            || data(for: appSettingsFileName) != nil
            || data(for: gpodderPrefsFileName) != nil
            || restoredMediaCount > 0
        else {
            throw DataBackupError.noPersistenceFiles
        }

        store.reloadFromPersistence()
        downloads.reloadAfterBackupImport()
        // Settings / gpodder already applied via snapshots (live @Published).
    }

    /// Write media payloads from the ZIP into Documents/downloads.
    /// - Merges with existing files (same fileName overwritten; unrelated local files left intact).
    /// - Catalog prune in `DownloadService.reloadAfterBackupImport` drops entries whose media is still missing.
    @discardableResult
    private static func restoreMediaFiles(from entries: [String: Data]) throws -> Int {
        let prefix = "\(mediaZipFolder)/"
        var written = 0
        try FileManager.default.createDirectory(
            at: DownloadService.downloadsDirectory,
            withIntermediateDirectories: true
        )
        for (key, payload) in entries {
            let normalized = key.hasPrefix("/") ? String(key.dropFirst()) : key
            // Accept "downloads/foo.mp3" or ".../downloads/foo.mp3"
            guard let slashRange = normalized.range(of: prefix, options: [.backwards]) else { continue }
            let afterPrefix = String(normalized[slashRange.upperBound...])
            // Only top-level downloads/file — no nested paths.
            guard !afterPrefix.isEmpty, !afterPrefix.contains("/"), isSafeMediaFileName(afterPrefix) else {
                continue
            }
            let dest = DownloadService.downloadsDirectory.appendingPathComponent(afterPrefix)
            try payload.write(to: dest, options: .atomic)
            written += 1
        }
        return written
    }

    /// Reject path traversal / empty names for media file basenames.
    private static func isSafeMediaFileName(_ name: String) -> Bool {
        guard !name.isEmpty, name != ".", name != ".." else { return false }
        if name.contains("/") || name.contains("\\") || name.contains("\0") { return false }
        return true
    }

    // MARK: - Helpers

    private static func encodeJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else {
            throw DataBackupError.encodeFailed
        }
        return data
    }

    private static func fileStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }
}
