import SwiftUI

/// Shared **Open episode website** control for Full player secondary + mini player ⋯.
///
/// Reuses `PodcastEpisode.websiteURL` (http(s) episode `link` only; never invents;
/// not enclosure / feed `siteLink`). Emits nothing when no usable URL.
/// Opens via SwiftUI `openURL` (system browser — **not** in-app WebView).
enum EpisodeOpenWebsite {
    /// Single Button for Full secondary HStack or mini ⋯ `Menu`.
    /// Returns `EmptyView` when `websiteURL` is nil.
    @ViewBuilder
    static func button(
        episode: PodcastEpisode,
        openURL: OpenURLAction
    ) -> some View {
        if let url = episode.websiteURL {
            Button {
                openURL(url)
            } label: {
                Label("Open episode website", systemImage: "safari")
            }
            .accessibilityLabel(String(localized: "Open episode website"))
            .accessibilityHint(String(localized: "Opens the feed-provided episode webpage http(s) link in the system browser — not an in-app WebView. No confirmation. Never uses the enclosure or podcast website URL. Distinct from Copy episode link, Copy media URL, and Share episode. Does not download, play, mark played, or change the queue."))
        }
    }
}
