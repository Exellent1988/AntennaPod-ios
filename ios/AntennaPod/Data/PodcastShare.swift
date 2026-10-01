import Foundation

extension PodcastEpisode {
    /// Prefer episode page/link URL; fall back to enclosure / media download URL.
    /// Local `file://` and local-folder feeds are not shareable as network links.
    var shareURL: URL? {
        if let link, !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let url = URL(string: link), !url.isFileURL {
            return url
        }
        if let downloadUrl, !downloadUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let url = URL(string: downloadUrl), !url.isFileURL {
            return url
        }
        return nil
    }
}

extension PodcastFeed {
    /// Feed / podcast RSS (or Atom) URL for sharing the subscription.
    /// Local folder feeds (`local-folder://`) are omitted — no network feed URL.
    var shareURL: URL? {
        if LocalFolderFeed.isLocalFolderFeedURL(feedUrl) { return nil }
        let trimmed = feedUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }
}
