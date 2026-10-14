import CarPlay
import UIKit

/// Async artwork for CarPlay rows: shared `AppURLSession`, in-memory downscaled cache, in-flight dedupe.
@MainActor
final class CarPlayArtworkLoader {
    static let shared = CarPlayArtworkLoader()

    private let cache = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    static var placeholder: UIImage? { UIImage(systemName: "music.note.list") }

    private var pixelSize: Int {
        let pts = CPListItem.maximumImageSize
        return CarPlayBrowseModel.artworkPixelSize(maxPoints: Double(max(pts.width, pts.height)), scale: 3)
    }

    func cached(_ url: String) -> UIImage? { cache.object(forKey: url as NSString) }

    func image(for url: String) async -> UIImage? {
        if let hit = cached(url) { return hit }
        if let task = inFlight[url] { return await task.value }
        let px = pixelSize
        let task = Task<UIImage?, Never> {
            guard let u = URL(string: url),
                  let (data, _) = try? await AppURLSession.shared.data(from: u),
                  let img = UIImage(data: data) else { return nil }
            let side = CGFloat(px)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
                img.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
            }
        }
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        if let result { cache.setObject(result, forKey: url as NSString) }
        return result
    }
}
