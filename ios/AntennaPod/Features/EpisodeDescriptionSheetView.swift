import SwiftUI
import UIKit

/// Scrollable episode shownotes / description sheet (plain text; HTML stripped for beta).
struct EpisodeDescriptionSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var playback: PlaybackService

    let episode: PodcastEpisode
    /// Optional podcast name for share message (`Title — Podcast`). When empty, looked up from the store.
    var feedTitle: String? = nil

    @State private var showCopiedAlert = false
    @State private var copiedAlertMessage = ""
    @State private var copyURLFeedbackTick = 0

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

    /// Only when this shownotes episode is the current playback item and position is known.
    private var canShareWithPosition: Bool {
        playback.currentEpisode?.id == episode.id
            && PodcastEpisode.canShareWithPosition(playback.positionSeconds)
    }

    private var shareMessageWithPosition: String {
        episode.shareMessage(
            feedTitle: resolvedFeedTitle,
            positionSeconds: playback.positionSeconds
        )
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

                        Button {
                            copyEpisodeLink(url)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .accessibilityLabel(String(localized: "Copy episode link"))
                        .accessibilityHint(String(localized: "Copies the episode webpage URL to the pasteboard"))
                    }
                    if let url = episode.mediaURL {
                        Button {
                            copyMediaURL(url)
                        } label: {
                            Image(systemName: "link")
                        }
                        .accessibilityLabel(String(localized: "Copy media URL"))
                        .accessibilityHint(String(localized: "Copies the episode media / enclosure URL to the pasteboard"))
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

                        if canShareWithPosition {
                            ShareLink(
                                item: url,
                                subject: Text(episode.title),
                                message: Text(shareMessageWithPosition)
                            ) {
                                Image(systemName: "square.and.arrow.up.on.square")
                            }
                            .accessibilityLabel(String(localized: "Share with position"))
                            .accessibilityHint(
                                String(localized: "Opens the system share sheet with the episode title, link, and current playback position")
                            )
                        }
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
            .alert(
                String(localized: "Copied"),
                isPresented: $showCopiedAlert
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(copiedAlertMessage)
            }
            .sensoryFeedback(.success, trigger: copyURLFeedbackTick)
        }
    }

    private func copyEpisodeLink(_ url: URL) {
        UIPasteboard.general.string = url.absoluteString
        copiedAlertMessage = String(localized: "Episode link copied to the pasteboard.")
        copyURLFeedbackTick += 1
        showCopiedAlert = true
    }

    private func copyMediaURL(_ url: URL) {
        UIPasteboard.general.string = url.absoluteString
        copiedAlertMessage = String(localized: "Media URL copied to the pasteboard.")
        copyURLFeedbackTick += 1
        showCopiedAlert = true
    }
}
