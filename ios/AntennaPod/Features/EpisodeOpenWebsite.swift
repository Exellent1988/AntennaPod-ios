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
            .accessibilityHint(String(localized: "Opens the episode webpage in the system browser"))
        }
    }
}
