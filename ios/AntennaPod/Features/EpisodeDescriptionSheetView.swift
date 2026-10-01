import SwiftUI

/// Scrollable episode shownotes / description sheet (plain text; HTML stripped for beta).
struct EpisodeDescriptionSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: PodcastStore

    let episode: PodcastEpisode
    /// Optional podcast name for share message (`Title — Podcast`). When empty, looked up from the store.
    var feedTitle: String? = nil

    private var plainDescription: String {
        guard let raw = episode.descriptionText else { return "" }
        return HTMLTextStripping.plainText(from: raw)
    }

    private var resolvedFeed: PodcastFeed? {
        store.feed(containingEpisodeId: episode.id)
    }

    private var resolvedFeedTitle: String {
        if let feedTitle, !feedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return feedTitle
        }
        return resolvedFeed?.title ?? ""
    }

    private var shareURL: URL? {
        episode.shareURL(feed: resolvedFeed)
    }

    private var shareMessage: String {
        episode.shareMessage(feedTitle: resolvedFeedTitle)
    }

    private var websiteURL: URL? {
        episode.websiteURL
    }

    var body: some View {
        NavigationStack {
            Group {
                if plainDescription.isEmpty {
                    ContentUnavailableView(
                        "No description",
                        systemImage: "doc.text",
                        description: Text("This episode has no shownotes in the feed.")
                    )
                } else {
                    ScrollView {
                        Text(plainDescription)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding()
                    }
                }
            }
            .navigationTitle("Shownotes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if let url = websiteURL {
                        Button {
                            openURL(url)
                        } label: {
                            Image(systemName: "safari")
                        }
                        .accessibilityLabel(String(localized: "Open episode website"))
                        .accessibilityHint(String(localized: "Opens the episode webpage in the system browser"))
                    }
                    if let url = shareURL {
                        ShareLink(
                            item: url,
                            subject: Text(episode.title),
                            message: Text(shareMessage)
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(String(localized: "Share episode"))
                        .accessibilityHint(String(localized: "Opens the system share sheet with the episode title and link"))
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Plain text — HTML tags stripped")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.bar)
            }
        }
    }
}
