import SwiftUI

/// Square episode artwork (Android EpisodeItemViewHolder cover): item image, else the podcast's artwork.
/// Loaded lazily per visible row via `AppAsyncImage` (respects the HTTP proxy); decorative for VoiceOver.
struct EpisodeArtworkThumbnail: View {
    @EnvironmentObject private var store: PodcastStore
    let episode: PodcastEpisode
    var size: CGFloat = 56

    private var url: URL? {
        let resolved = store.episode(id: episode.id) ?? episode
        return resolved.artworkURL(feed: store.feed(containingEpisodeId: episode.id)).flatMap(URL.init(string:))
    }

    var body: some View {
        Group {
            if let url {
                AppAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.14, style: .continuous))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            Color.secondary.opacity(0.15)
            Image(systemName: "mic").foregroundStyle(.secondary)
        }
    }
}
