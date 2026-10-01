import SwiftUI
import UIKit

/// Feed-provided `podcast:chapters` remote URL — **Open** http(s) / **Copy**.
/// Shown when the episode has a chapters URL. Does **not** replace the in-app chapter list
/// (PSC inline / lazy Podcast Index JSON via `PodcastIndexChapterParser` / media-file tags).
/// Cap honesty: display-only URL actions; existing feeds need refresh to pick up `type`.
struct PodcastChaptersURLView: View {
    @Environment(\.openURL) private var openURL

    let episode: PodcastEpisode
    /// When embedded under an existing Chapters header, skip the local title.
    var showsSectionTitle: Bool = true

    @State private var showCopiedAlert = false
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
                        copyURL(raw)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(String(localized: "Copy chapters URL"))
                    .accessibilityHint(String(localized: "Copies the feed chapters URL to the pasteboard"))
                }

                Text(
                    String(
                        localized: "Remote chapters URL from the feed. The in-app chapter list still uses Podlove Simple Chapters, lazily fetched Podcast Index JSON when the Full Player opens, or local media-file tags — Open / Copy only opens or copies this URL."
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
                Text(String(localized: "Chapters URL copied to the pasteboard."))
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

    private func copyURL(_ string: String) {
        UIPasteboard.general.string = string
        copyFeedbackTick &+= 1
        showCopiedAlert = true
    }
}
