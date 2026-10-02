import SwiftUI
import UIKit

/// Label-style **Copy episode link** + **Copy media URL** for an episode.
///
/// Reuses `PodcastEpisode.websiteURL` / `mediaURL` (http(s) only; never invents;
/// `file://` / `local-folder` omitted). Emits nothing when neither URL is usable.
/// Pasteboard helpers shared with Full player / Shownotes / EpisodeRow callers.
/// Used by Full player secondary (via helpers) + mini player ⋯ (via `labelStyle`).
enum EpisodeCopyLinks {
    /// Copies the episode webpage URL string; returns the localized Copied alert body.
    static func copyEpisodeLink(_ url: URL) -> String {
        UIPasteboard.general.string = url.absoluteString
        return String(localized: "Episode link copied to the pasteboard.")
    }

    /// Copies the enclosure / media URL string; returns the localized Copied alert body.
    static func copyMediaURL(_ url: URL) -> String {
        UIPasteboard.general.string = url.absoluteString
        return String(localized: "Media URL copied to the pasteboard.")
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
            .accessibilityHint(String(localized: "Copies the episode webpage URL to the pasteboard"))
        }

        if let url = episode.mediaURL {
            Button {
                onCopied(copyMediaURL(url))
            } label: {
                Label("Copy media URL", systemImage: "link")
            }
            .accessibilityLabel(String(localized: "Copy media URL"))
            .accessibilityHint(String(localized: "Copies the episode media / enclosure URL to the pasteboard"))
        }
    }
}
