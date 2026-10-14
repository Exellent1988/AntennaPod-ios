import SwiftUI
import UIKit

/// Feed-provided `podcast:chapters` remote URL — **Open** http(s) / **Copy** / **Share** —
/// plus optional type-caption **Copy** / **Share**.
/// Shown when the episode has a chapters URL. Does **not** replace the in-app chapter list
/// (PSC inline / lazy Podcast Index JSON via `PodcastIndexChapterParser` / media-file tags).
/// Cap honesty: display-only URL/type actions; existing feeds need refresh to pick up `type`.
struct PodcastChaptersURLView: View {
    @Environment(\.openURL) private var openURL

    let episode: PodcastEpisode
    /// When embedded under an existing Chapters header, skip the local title.
    var showsSectionTitle: Bool = true

    @State private var showCopiedAlert = false
    @State private var copiedMessage = String(localized: "Chapters URL copied to the pasteboard.")
    @State private var copyFeedbackTick = 0

    private var openableURL: URL? {
        episode.podcastIndexChapterOpenURL
    }

    private var rawURLString: String? {
        guard let raw = episode.podcastIndexChapterUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return raw
    }

    private var typeCaption: String? {
        episode.displayPodcastIndexChapterType
    }

    var body: some View {
        if episode.hasPodcastIndexChapterURL, let raw = rawURLString {
            VStack(alignment: .leading, spacing: 8) {
                if showsSectionTitle {
                    Text("Chapters URL")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                }

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(raw)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        if let typeCaption {
                            Text(typeCaption)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(accessibilityLabel(raw: raw, type: typeCaption))

                    if let url = openableURL {
                        Button {
                            openURL(url)
                        } label: {
                            Image(systemName: "safari")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(String(localized: "Open chapters URL"))
                        .accessibilityHint(String(localized: "Opens the feed chapters file in the system browser"))
                    }

                    Button {
                        copyToPasteboard(raw, confirmation: String(localized: "Chapters URL copied to the pasteboard."))
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(String(localized: "Copy chapters URL"))
                    .accessibilityHint(String(localized: "Copies the feed chapters URL to the pasteboard"))

                    if let typeCaption {
                        Button {
                            copyToPasteboard(
                                typeCaption,
                                confirmation: String(localized: "Chapters type copied to the pasteboard.")
                            )
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(String(localized: "Copy chapters type"))
                        .accessibilityHint(
                            String(localized: "Copies the feed chapters type to the pasteboard")
                        )

                        ShareLink(item: typeCaption) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(String(localized: "Share chapters type"))
                        .accessibilityHint(
                            String(localized: "Shares the feed chapters type, not the in-app table of contents export")
                        )
                    }

                    if let url = openableURL {
                        ShareLink(
                            item: url,
                            subject: Text(episode.title),
                            message: Text(String(localized: "Remote chapters URL from the feed."))
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(String(localized: "Share chapters URL"))
                        .accessibilityHint(
                            String(localized: "Shares the remote feed chapters URL, not the in-app table of contents export")
                        )
                    } else {
                        ShareLink(
                            item: raw,
                            subject: Text(episode.title),
                            message: Text(String(localized: "Remote chapters URL from the feed."))
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(String(localized: "Share chapters URL"))
                        .accessibilityHint(
                            String(localized: "Shares the remote feed chapters URL, not the in-app table of contents export")
                        )
                    }
                }

                Text(
                    String(
                        localized: "Remote chapters URL from the feed. The in-app chapter list still uses Podlove Simple Chapters, lazily fetched Podcast Index JSON when the Full Player opens, or local media-file tags — URL actions only open, copy, or share this URL; when present, the separate type actions copy or share the exact feed-provided caption."
                    )
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .alert(String(localized: "Copied"), isPresented: $showCopiedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(copiedMessage)
            }
            .sensoryFeedback(.success, trigger: copyFeedbackTick)
        }
    }

    private func accessibilityLabel(raw: String, type: String?) -> String {
        var parts: [String] = [String(localized: "Chapters URL"), raw]
        if let type {
            parts.append(String(localized: "Type \(type)"))
        }
        return parts.joined(separator: ", ")
    }

    private func copyToPasteboard(_ string: String, confirmation: String) {
        UIPasteboard.general.string = string
        copiedMessage = confirmation
        copyFeedbackTick &+= 1
        showCopiedAlert = true
    }
}
