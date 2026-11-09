import CarPlay
import UIKit

/// Artwork for CarPlay rows and Now Playing: shared `AppURLSession`, aspect-fit into a padded
/// square (no stretching), memory `NSCache` + disk cache in Caches/CarPlayArtwork (survives relaunch,
/// 50 MB LRU by mtime), in-flight dedupe, and prefetch. Download, decode, resize, and disk I/O run
/// off the main actor.
@MainActor
final class CarPlayArtworkLoader {
    static let shared = CarPlayArtworkLoader()

    private let cache = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private var writesSinceTrim = 0
    nonisolated let directory: URL? = {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("CarPlayArtwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {
        Task.detached(priority: .utility) { [directory] in Self.trimDisk(directory) }
    }

    static var placeholder: UIImage? { UIImage(systemName: "music.note.list") }

    /// List-row pixel size (CarPlay max item image size × 3).
    var listPixels: Int {
        let pts = CPListItem.maximumImageSize
        return CarPlayBrowseModel.artworkPixelSize(maxPoints: Double(max(pts.width, pts.height)), scale: 3)
    }

    static let nowPlayingPixels = 600

    private func key(_ url: String, _ px: Int) -> String { "\(px)|\(url)" }

    /// Memory-cache hit only (cheap; safe to call while building list items).
    func cached(_ url: String, pixels: Int? = nil) -> UIImage? {
        cache.object(forKey: key(url, pixels ?? listPixels) as NSString)
    }

    func image(for url: String, pixels: Int? = nil) async -> UIImage? {
        let px = pixels ?? listPixels
        let k = key(url, px)
        if let hit = cache.object(forKey: k as NSString) { return hit }
        if let task = inFlight[k] { return await task.value }
        let file = directory?.appendingPathComponent(NowPlayingLogic.cacheFileName(url: url, pixels: px))
        let task = Task.detached(priority: .utility) { () -> UIImage? in
            if let file, let img = Self.readDisk(file) { return img }
            guard let u = URL(string: url),
                  let (data, _) = try? await AppURLSession.shared.data(from: u),
                  let img = UIImage(data: data) else { return nil }
            let out = Self.render(img, side: px)
            if let file, let png = out.pngData() { try? png.write(to: file, options: .atomic) }
            return out
        }
        inFlight[k] = task
        let result = await task.value
        inFlight[k] = nil
        if let result {
            cache.setObject(result, forKey: k as NSString)
            writesSinceTrim += 1
            if writesSinceTrim >= 50 {
                writesSinceTrim = 0
                Task.detached(priority: .utility) { [directory] in Self.trimDisk(directory) }
            }
        }
        return result
    }

    /// Warm caches for upcoming rows (bounded so a 100-row list does not flood the network).
    func prefetch(_ urls: [String], limit: Int = 24) {
        for url in urls.prefix(limit) where cached(url) == nil && inFlight[key(url, listPixels)] == nil {
            Task { _ = await image(for: url) }
        }
    }

    // MARK: Off-main helpers

    /// Read + touch mtime (LRU).
    nonisolated private static func readDisk(_ file: URL) -> UIImage? {
        guard let img = UIImage(contentsOfFile: file.path) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
        return img.preparingForDisplay() ?? img
    }

    nonisolated static func trimDisk(_ directory: URL?, limit: Int64 = NowPlayingLogic.diskCacheLimitBytes) {
        guard let directory else { return }
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: .skipsHiddenFiles) else { return }
        let entries = files.compactMap { f -> NowPlayingLogic.CacheEntry? in
            guard let v = try? f.resourceValues(forKeys: Set(keys)) else { return nil }
            return .init(name: f.lastPathComponent, bytes: Int64(v.fileSize ?? 0), modified: v.contentModificationDate ?? .distantPast)
        }
        for name in NowPlayingLogic.evictions(entries, limit: limit) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    /// Aspect-fit into a square with padding; transparent letterbox. Thread-safe (UIGraphicsImageRenderer).
    nonisolated static func render(_ img: UIImage, side px: Int) -> UIImage {
        let side = Double(px)
        let w = Double(img.size.width), h = Double(img.size.height)
        let pad = NowPlayingLogic.padding(imageWidth: w, imageHeight: h, side: side)
        let r = NowPlayingLogic.aspectFitRect(imageWidth: w, imageHeight: h, side: side, padding: pad)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            img.draw(in: CGRect(x: r.x, y: r.y, width: r.width, height: r.height))
        }
    }
}
