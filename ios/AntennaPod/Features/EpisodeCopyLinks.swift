import SwiftUI
import UIKit

/// Label-style episode copy/share actions for feed-provided text and URLs.
///
/// Reuses `PodcastEpisode.websiteURL` / `mediaURLString` (feed-provided http(s) only;
/// never invents; `file://` / `local-folder` omitted). Emits nothing when neither URL is usable.
/// Pasteboard helpers shared with Full player / Shownotes / EpisodeRow callers.
/// Used by Full player secondary (via helpers) + mini player ⋯ (via `labelStyle`).
@MainActor
enum EpisodeCopyLinks {
    /// Feed or saved playback duration used by EpisodeRow metadata captions.
    /// A live player duration can be supplied by callers that have media metadata; never invents.
    static func knownDurationSeconds(
        for episode: PodcastEpisode,
        liveDurationSeconds: Double? = nil,
        savedDurationSeconds: Double? = nil
    ) -> Double? {
        if episode.hasKnownDuration { return episode.durationSeconds }
        if let liveDurationSeconds, liveDurationSeconds.isFinite, liveDurationSeconds > 0 {
            return liveDurationSeconds
        }
        if let savedDurationSeconds, savedDurationSeconds.isFinite, savedDurationSeconds > 0 {
            return savedDurationSeconds
        }
        return nil
    }

    /// Same publish-date caption used by EpisodeRow (Today / Yesterday / N days ago / medium absolute).
    /// Returns nil when the feed did not provide a publish timestamp; never invents a date.
    static func formattedPublishDate(for episode: PodcastEpisode) -> String? {
        guard let milliseconds = episode.pubDateEpochMs else { return nil }
        return EpisodeDateFormatting.listCaption(
            for: Date(timeIntervalSince1970: Double(milliseconds) / 1000)
        )
    }

    /// Same human-readable duration caption used by episode metadata surfaces.
    static func formattedDuration(
        for episode: PodcastEpisode,
        liveDurationSeconds: Double? = nil,
        savedDurationSeconds: Double? = nil
    ) -> String? {
        PodcastEpisode.formatPlaybackPosition(
            knownDurationSeconds(
                for: episode,
                liveDurationSeconds: liveDurationSeconds,
                savedDurationSeconds: savedDurationSeconds
            )
        )
    }

    /// Prefer the on-disk copy's size, then the feed enclosure size; hide unknown/zero values.
    static func knownByteSize(for episode: PodcastEpisode, downloads: DownloadService) -> Int64? {
        if let item = downloads.downloads.first(where: { $0.id == episode.id }) {
            if let size = item.localFileByteSize() { return size }
            // Retain the persisted feed enclosure value when a download row is stale.
            if item.episode.size > 0 { return item.episode.size }
        }
        if let url = downloads.localURL(for: episode) {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile != false, let size = values?.fileSize, size > 0 {
                return Int64(size)
            }
        }
        return episode.size > 0 ? episode.size : nil
    }

    /// Same human-readable file-size caption used by episode metadata surfaces.
    static func formattedByteSize(for episode: PodcastEpisode, downloads: DownloadService) -> String? {
        guard let bytes = knownByteSize(for: episode, downloads: downloads) else { return nil }
        return DownloadStorageUsage.formatBytes(bytes)
    }
    /// Feed-provided episode title trimmed for plain-text copy/share; hide when empty.
    static func trimmedTitle(for episode: PodcastEpisode) -> String? {
        let title = episode.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    /// Feed display title trimmed for plain-text copy/share; hide when empty.
    static func trimmedFeedTitle(_ title: String?) -> String? {
        guard let title else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Combined plain-text line used by title/podcast copy and share actions.
    /// Hidden unless both feed-provided values are non-empty; never invents a podcast name.
    static func trimmedTitleAndPodcast(episode: PodcastEpisode, feedTitle: String?) -> String? {
        guard let title = trimmedTitle(for: episode),
              let podcast = trimmedFeedTitle(feedTitle) else { return nil }
        return "\(title) — \(podcast)"
    }

    /// Copies the combined `title — podcast` line; returns the localized Copied alert body.
    static func copyTitleAndPodcast(_ text: String) -> String {
        UIPasteboard.general.string = text
        return String(localized: "Title and podcast copied to the pasteboard.")
    }

    /// Copies the trimmed podcast display title; returns the localized Copied alert body.
    static func copyPodcastTitle(_ title: String) -> String {
        UIPasteboard.general.string = title
        return String(localized: "Podcast title copied to the pasteboard.")
    }

    /// Copies the trimmed episode title; returns the localized Copied alert body.
    static func copyEpisodeTitle(_ title: String) -> String {
        UIPasteboard.general.string = title
        return String(localized: "Episode title copied to the pasteboard.")
    }

    /// Copies the episode webpage URL string; returns the localized Copied alert body.
    static func copyEpisodeLink(_ url: URL) -> String {
        UIPasteboard.general.string = url.absoluteString
        return String(localized: "Episode link copied to the pasteboard.")
    }

    /// Copies the feed-provided enclosure / media URL string; returns the localized alert body.
    static func copyMediaURL(_ string: String) -> String {
        UIPasteboard.general.string = string
        return String(localized: "Media URL copied to the pasteboard.")
    }

    /// URL overload for callers that already parsed the media URL.
    static func copyMediaURL(_ url: URL) -> String {
        copyMediaURL(url.absoluteString)
    }

    /// Sibling `Button`s for `Menu` / `HStack` (same `@ViewBuilder` pattern as
    /// `EpisodeShareLinks`). Hidden independently when the matching URL is absent.
    @ViewBuilder
    static func labelStyle(
        episode: PodcastEpisode,
        onCopied: @escaping (String) -> Void
    ) -> some View {
        if let url = episode.websiteURL {
            Button {
                onCopied(copyEpisodeLink(url))
            } label: {
                Label("Copy episode link", systemImage: "doc.on.doc")
            }
            .accessibilityLabel(String(localized: "Copy episode link"))
            .accessibilityHint(String(localized: "Copies the feed-provided episode webpage http(s) link to the pasteboard. No confirmation. Never silently copies the enclosure as the episode link. Distinct from Copy media URL and Share episode. Does not open the browser, download, play, mark played, or change the queue."))

            // Keep the webpage ShareLink directly beside its Copy twin in every caller.
            EpisodeShareLinks.episodeLinkLabelStyle(episode: episode)
        }

        if let raw = episode.mediaURLString {
            Button {
                onCopied(copyMediaURL(raw))
            } label: {
                Label("Copy media URL", systemImage: "link")
            }
            .accessibilityLabel(String(localized: "Copy media URL"))
            .accessibilityHint(String(localized: "Copies the feed-provided episode media / enclosure http(s) URL to the pasteboard. No confirmation. Hidden for local file or local-folder URLs. Distinct from Copy episode link and Share episode. Does not download, play, mark played, or change the queue."))
        }
    }
}
