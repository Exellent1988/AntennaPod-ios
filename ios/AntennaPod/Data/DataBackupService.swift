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

    static func make(files: [String], createdAt: Date = Date()) -> DataBackupManifest {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return DataBackupManifest(
            format: formatID,
            version: currentVersion,
            createdAtISO8601: formatter.string(from: createdAt),
            includesMedia: false,
            includesKeychainSecrets: false,
            files: files.sorted(),
            notes: [
                "iOS Application Support JSON backup — not AntennaPod Android database export.",
                "Downloads: catalog metadata only (downloads.json); media under Documents/downloads is not included — re-download offline files.",
                "Keychain secrets are NOT included (gpodder password, Podcast Index API key/secret, Parental controls PIN). Re-enter passwords/keys after import on a new device.",
                "pending-downloads.json (in-flight tasks) is omitted.",
                "HTML subscription export is separate (Settings → Import / Export), not part of this ZIP."
            ]
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

    var errorDescription: String? {
        switch self {
        case .missingManifest:
            return "Backup is missing manifest.json"
        case .unsupportedFormat(let f):
            return "Unsupported backup format “\(f)” (need \(DataBackupManifest.formatID))"
        case .unsupportedVersion(let v):
            return "Unsupported backup version \(v)"
        case .noPersistenceFiles:
            return "Backup contains no recognizable persistence files"
        case .encodeFailed:
            return "Could not encode backup payload"
        case .importFailed(let msg):
            return msg
        }
    }
}

/// Export / import of local iOS JSON persistence (+ AppSettings + gpodder prefs; no Keychain, no media).
enum DataBackupService {
    static let manifestFileName = "manifest.json"
    static let appSettingsFileName = "app-settings.json"
    static let gpodderPrefsFileName = "gpodder-prefs.json"

    /// Application Support JSON files included in MVP backup (catalog only for downloads).
    static let persistenceFileNames: [String] = [
        "feeds.json",
        "queue.json",
        "playback.json",
        "downloads.json",
        "feed-settings.json",
        "favorites.json",
        "archived.json",
        "feed-tags.json",
        "download-errors.json"
    ]

    // MARK: - Export

    /// Build a STORE-compressed ZIP in a temporary directory and return its file URL for the share sheet.
    @MainActor
    static func exportTemporaryZip(
        settings: AppSettings,
        gpodder: GpodderSyncService
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

        let fileList = entries.map(\.name) + [manifestFileName]
        let manifest = DataBackupManifest.make(files: fileList)
        let manifestData = try encodeJSON(manifest)
        entries.insert((manifestFileName, manifestData), at: 0)

        let stamp = Self.fileStamp(Date())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AntennaPod-iOS-Backup-\(stamp).zip", isDirectory: false)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try MinimalZip.writeStoreArchive(entries: entries, to: url)
        return url
    }

    // MARK: - Import

    /// Replace persistence + prefs from a backup ZIP. Caller must confirm replace first.
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

        var wrotePersistence = false
        for name in persistenceFileNames {
            guard let payload = data(for: name) else { continue }
            try PodcastPersistence.writeFile(name: name, data: payload)
            wrotePersistence = true
        }
        // Clear in-flight download map — not meaningful across restore.
        PodcastPersistence.savePendingDownloads([])

        if let settingsPayload = data(for: appSettingsFileName) {
            let snap = try JSONDecoder().decode(AppSettingsBackupSnapshot.self, from: settingsPayload)
            settings.applyBackupSnapshot(snap)
        }

        if let gpodderPayload = data(for: gpodderPrefsFileName) {
            let snap = try JSONDecoder().decode(GpodderBackupSnapshot.self, from: gpodderPayload)
            gpodder.applyBackupSnapshot(snap)
        }

        guard wrotePersistence
            || data(for: appSettingsFileName) != nil
            || data(for: gpodderPrefsFileName) != nil
        else {
            throw DataBackupError.noPersistenceFiles
        }

        store.reloadFromPersistence()
        downloads.reloadAfterBackupImport()
        // Settings / gpodder already applied via snapshots (live @Published).
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
