import CryptoKit
import Foundation
import PodcastCore

/// Disk cache for cover images in Caches/covers (Android Glide disk cache, `prefImageCacheSize`).
/// One file per URL (SHA-256 name), LRU by file modification date, trimmed to the size limit after
/// each write. A hit is served from disk on any network; a miss is fetched only when
/// `MobileDataGate` allows images (Images Wi‑Fi only → nothing new over mobile data, offline never).
/// iOS may purge Caches under storage pressure — covers are then fetched again.
@MainActor
final class CoverDiskCache {
    static let shared = CoverDiskCache()

    let directory: URL
    /// Size limit in bytes (Settings → Storage → Image cache size).
    var limitBytes: Int64
    /// Test seam: replaces the network fetch.
    var fetchOverride: ((URL) async throws -> Data)?

    init(directory: URL? = nil, limitBytes: Int64 = Int64(CoverCachePolicy.defaultSizeMB) * 1_048_576) {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.directory = directory ?? base.appendingPathComponent("covers", isDirectory: true)
        self.limitBytes = limitBytes
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    enum CoverError: Error { case notCachedOnMobileData }

    func fileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest)
    }

    /// Cached bytes if present (touches the access date).
    func cachedData(for url: URL) -> Data? {
        let file = fileURL(for: url)
        guard let data = try? Data(contentsOf: file), !data.isEmpty else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
        return data
    }

    /// Disk hit, else network (when the mobile-data gate allows images), then store + trim.
    func data(for url: URL, settings: AppSettings? = nil) async throws -> Data {
        if let hit = cachedData(for: url) { return hit }
        guard MobileDataGate.allows(.images, settings: settings) else { throw CoverError.notCachedOnMobileData }
        let data: Data
        if let fetchOverride {
            data = try await fetchOverride(url)
        } else {
            let (fetched, _) = try await AppURLSession.shared.data(for: MobileDataGate.imageRequest(for: url, settings: settings))
            data = fetched
        }
        store(data, for: url)
        return data
    }

    func store(_ data: Data, for url: URL) {
        guard !data.isEmpty else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: url), options: .atomic)
        trim()
    }

    private func entries() -> [CoverCachePolicy.Entry] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return files.compactMap { f in
            let v = try? f.resourceValues(forKeys: Set(keys))
            return CoverCachePolicy.Entry(name: f.lastPathComponent, bytes: Int64(v?.fileSize ?? 0),
                                          lastAccess: v?.contentModificationDate ?? .distantPast)
        }
    }

    func trim() {
        for name in CoverCachePolicy.evictions(entries(), limitBytes: limitBytes) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    var usageBytes: Int64 { entries().reduce(0) { $0 + $1.bytes } }

    func clear() {
        for e in entries() { try? FileManager.default.removeItem(at: directory.appendingPathComponent(e.name)) }
    }
}
