import CarPlay
import UIKit

/// Artwork for CarPlay rows and Now Playing: shared `AppURLSession`, aspect-fit into a padded
/// square (no stretching), memory `NSCache` + disk cache in Caches/CarPlayArtwork (survives relaunch),
/// in-flight dedupe, and prefetch.
@MainActor
final class CarPlayArtworkLoader {
    static let shared = CarPlayArtworkLoader()

    private let cache = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private let directory: URL? = {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("CarPlayArtwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static var placeholder: UIImage? { UIImage(systemName: "music.note.list") }

    /// List-row pixel size (CarPlay max item image size × 3).
    var listPixels: Int {
        let pts = CPListItem.maximumImageSize
        return CarPlayBrowseModel.artworkPixelSize(maxPoints: Double(max(pts.width, pts.height)), scale: 3)
    }

    /// Now Playing pixel size.
    static let nowPlayingPixels = 600

    private func key(_ url: String, _ px: Int) -> NSString { "\(px)|\(url)" as NSString }

    func cached(_ url: String, pixels: Int? = nil) -> UIImage? {
        let px = pixels ?? listPixels
        if let hit = cache.object(forKey: key(url, px)) { return hit }
        guard let file = directory?.appendingPathComponent(NowPlayingLogic.cacheFileName(url: url, pixels: px)),
              let img = UIImage(contentsOfFile: file.path) else { return nil }
        cache.setObject(img, forKey: key(url, px))
        return img
    }

    func image(for url: String, pixels: Int? = nil) async -> UIImage? {
        let px = pixels ?? listPixels
        if let hit = cached(url, pixels: px) { return hit }
        let k = key(url, px) as String
        if let task = inFlight[k] { return await task.value }
        let file = directory?.appendingPathComponent(NowPlayingLogic.cacheFileName(url: url, pixels: px))
        let task = Task<UIImage?, Never> {
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
        if let result { cache.setObject(result, forKey: key(url, px)) }
        return result
    }

    /// Warm caches for upcoming rows (bounded so a 100-row list does not flood the network).
    func prefetch(_ urls: [String], limit: Int = 24) {
        for url in urls.prefix(limit) where cached(url) == nil && inFlight[key(url, listPixels) as String] == nil {
            Task { _ = await image(for: url) }
        }
    }

    /// Aspect-fit into a square with padding; transparent letterbox.
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
