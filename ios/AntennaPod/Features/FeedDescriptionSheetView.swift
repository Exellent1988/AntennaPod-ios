import SwiftUI

/// Scrollable podcast / feed description sheet (plain text; HTML stripped for beta).
/// Parallel to `EpisodeDescriptionSheetView` shownotes. Uses `PodcastFeed.descriptionText` only —
/// no author field on the model in this beta.
struct FeedDescriptionSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let feed: PodcastFeed

    private var plainDescription: String {
        guard let raw = feed.descriptionText else { return "" }
        return HTMLTextStripping.plainText(from: raw)
    }

    private var websiteURL: URL? {
        feed.websiteURL
    }

    var body: some View {
        NavigationStack {
            Group {
                if plainDescription.isEmpty {
                    ContentUnavailableView(
                        "No description",
                        systemImage: "info.circle",
                        description: Text("This podcast has no description in the feed.")
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(feed.title)
                                .font(.title2.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityAddTraits(.isHeader)

                            Text(plainDescription)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Description")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if let url = websiteURL {
                        Button {
                            openURL(url)
                        } label: {
                            Image(systemName: "safari")
                        }
                        .accessibilityLabel(String(localized: "Open podcast website"))
                        .accessibilityHint(String(localized: "Opens the podcast webpage in the system browser"))
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
