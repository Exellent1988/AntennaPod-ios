import Foundation

extension PodcastEpisode {
    /// Prefer episode page/link URL; fall back to enclosure / media download URL.
    var shareURL: URL? {
        if let link, !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let url = URL(string: link) {
            return url
        }
        if let downloadUrl, !downloadUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let url = URL(string: downloadUrl) {
            return url
        }
        return nil
    }
}

extension PodcastFeed {
    /// Feed / podcast RSS (or Atom) URL for sharing the subscription.
    var shareURL: URL? {
        let trimmed = feedUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }
}
