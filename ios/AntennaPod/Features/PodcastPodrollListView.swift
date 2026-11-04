import SwiftUI
import UIKit

/// Feed-provided channel `podcast:podroll` / nested `podcast:remoteItem` list.
/// Title + url/guid when present; **Open** http(s) feed URL; **Copy** / **Share**; **Subscribe** via existing
/// `FeedPreviewRequest` preview when feedUrl is http(s). Cap + honesty footnote.
/// **Display-only** — never invent recommendations; no Podcast Index GUID resolution.
/// Hidden when none.
struct PodcastPodrollListView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: PodcastStore

    let items: [PodcastRemoteItem]
    /// Section title (localized by caller).
    var title: String = String(localized: "Recommended podcasts")

    @State private var showCopiedAlert = false
    @State private var copiedAlertMessage = String(localized: "Recommendation copied to the pasteboard.")
    @State private var copyFeedbackTick = 0
    @State private var previewRequest: FeedPreviewRequest?

    private var capped: (shown: [PodcastRemoteItem], truncated: Bool) {
        PodcastPodrollDisplay.capped(items)
    }

    var body: some View {
        let result = capped
        if !result.shown.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)

                ForEach(Array(result.shown.enumerated()), id: \.offset) { _, entry in
                    podrollRow(entry)
                }

                Text(
                    String(
                        localized: "These recommendations come from the feed (podcast:podroll). Open or copy a feed URL, or preview Subscribe when a URL is present — this app does not invent shows or resolve Podcast Index GUIDs."
                    )
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityLabel(
                    String(
                        localized: "These recommendations come from the feed (podcast:podroll). Open or copy a feed URL, or preview Subscribe when a URL is present — this app does not invent shows or resolve Podcast Index GUIDs."
                    )
                )

                if result.truncated {
                    Text(String(localized: "Showing first 20 recommended podcasts from the feed."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(
                            String(localized: "Showing first 20 recommended podcasts from the feed.")
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .alert(String(localized: "Copied"), isPresented: $showCopiedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(copiedAlertMessage)
            }
            .sensoryFeedback(.success, trigger: copyFeedbackTick)
            .sheet(item: $previewRequest) { request in
                NavigationStack {
                    FeedPreviewView(request: request)
                }
                .environmentObject(store)
            }
        }
    }

    @ViewBuilder
    private func podrollRow(_ entry: PodcastRemoteItem) -> some View {
        let label = entry.primaryLabel ?? ""
        let url = entry.openURL
        let copyText = PodcastPodrollDisplay.copyText(entry)
        let guid = entry.displayFeedGuid
        let itemGuid = entry.displayItemGuid
        let a11y: String = {
            var parts: [String] = [String(localized: "Recommended podcast")]
            if let title = entry.displayTitle {
                parts.append(title)
            }
            if let feedUrl = entry.displayFeedUrl {
                parts.append(feedUrl)
            }
            if let guid {
                parts.append(String(localized: "Feed GUID \(guid)"))
            }
            if let itemGuid {
                parts.append(String(localized: "Item GUID \(itemGuid)"))
            }
            if let medium = entry.displayMedium {
                parts.append(String(localized: "Medium \(medium)"))
            }
            return parts.joined(separator: ", ")
        }()

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(a11y)

            if entry.displayTitle != nil || entry.displayFeedUrl != nil || guid != nil || itemGuid != nil {
                // Secondary lines: only feed-provided URL/GUID values; never resolve identifiers.
                if let feedUrl = entry.displayFeedUrl {
                    Text(feedUrl)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                        .accessibilityHidden(true)
                }
                if let guid {
                    Text(guid)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                        .accessibilityHidden(true)
                }
                if let itemGuid {
                    Text(itemGuid)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                        .accessibilityHidden(true)
                }
            }

            if let medium = entry.displayMedium {
                Text(medium)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            HStack(spacing: 12) {
                if let title = entry.displayTitle {
                    Button {
                        UIPasteboard.general.string = title
                        copiedAlertMessage = String(localized: "Recommendation title copied to the pasteboard.")
                        copyFeedbackTick += 1
                        showCopiedAlert = true
                    } label: {
                        Label("Copy recommendation title", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy recommendation title"))
                    .accessibilityHint(
                        String(localized: "Copies the exact feed-provided recommended podcast title as plain text")
                    )

                    ShareLink(item: title) {
                        Label("Share recommendation title", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share recommendation title"))
                    .accessibilityHint(
                        String(localized: "Shares the exact feed-provided recommended podcast title as plain text")
                    )
                }

                if let guid {
                    Button {
                        UIPasteboard.general.string = guid
                        copiedAlertMessage = String(localized: "Recommendation feed GUID copied to the pasteboard.")
                        copyFeedbackTick += 1
                        showCopiedAlert = true
                    } label: {
                        Label("Copy recommendation feed GUID", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy recommendation feed GUID"))
                    .accessibilityHint(
                        String(localized: "Copies the exact feed-provided recommendation feed GUID as plain text")
                    )

                    ShareLink(item: guid, subject: Text(label)) {
                        Label("Share recommendation feed GUID", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share recommendation feed GUID"))
                    .accessibilityHint(
                        String(localized: "Shares the exact feed-provided recommendation feed GUID as plain text")
                    )
                }

                if let itemGuid {
                    Button {
                        UIPasteboard.general.string = itemGuid
                        copiedAlertMessage = String(localized: "Recommendation item GUID copied to the pasteboard.")
                        copyFeedbackTick += 1
                        showCopiedAlert = true
                    } label: {
                        Label("Copy recommendation item GUID", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy recommendation item GUID"))
                    .accessibilityHint(
                        String(localized: "Copies the exact feed-provided recommendation item GUID as plain text")
                    )

                    ShareLink(item: itemGuid, subject: Text(label)) {
                        Label("Share recommendation item GUID", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share recommendation item GUID"))
                    .accessibilityHint(
                        String(localized: "Shares the exact feed-provided recommendation item GUID as plain text")
                    )
                }

                if let medium = entry.displayMedium {
                    Button {
                        UIPasteboard.general.string = medium
                        copiedAlertMessage = String(localized: "Recommendation medium copied to the pasteboard.")
                        copyFeedbackTick += 1
                        showCopiedAlert = true
                    } label: {
                        Label("Copy recommendation medium", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy recommendation medium"))
                    .accessibilityHint(String(localized: "Copies the exact feed-provided recommended podcast medium as plain text"))

                    ShareLink(item: medium, subject: Text(label)) {
                        Label("Share recommendation medium", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share recommendation medium"))
                    .accessibilityHint(String(localized: "Shares the exact feed-provided recommended podcast medium as plain text"))
                }

                Button {
                    UIPasteboard.general.string = PodcastPodrollDisplay.copyText(entry)
                    copiedAlertMessage = String(localized: "Recommendation copied to the pasteboard.")
                    copyFeedbackTick += 1
                    showCopiedAlert = true
                } label: {
                    Label("Copy recommendation", systemImage: "doc.on.doc")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Copy recommendation"))
                .accessibilityHint(
                    String(localized: "Copies the complete feed-provided recommended podcast entry to the pasteboard")
                )

                if !copyText.isEmpty {
                    Group {
                        if let url {
                            ShareLink(item: url) {
                                Label("Share recommendation", systemImage: "square.and.arrow.up")
                                    .font(.subheadline)
                            }
                        } else {
                            ShareLink(item: copyText) {
                                Label("Share recommendation", systemImage: "square.and.arrow.up")
                                    .font(.subheadline)
                            }
                        }
                    }
                    .accessibilityLabel(String(localized: "Share recommendation"))
                    .accessibilityHint(
                        String(
                            localized: "Shares the recommended feed URL when it is a parseable http(s) URL; otherwise shares the same complete feed-provided entry as Copy"
                        )
                    )
                }

                if let url {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Open", systemImage: "safari")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Open"))
                    .accessibilityHint(
                        String(localized: "Opens the recommended feed URL in the system browser")
                    )

                    Button {
                        previewRequest = FeedPreviewRequest(
                            feedUrl: url.absoluteString,
                            hintTitle: entry.displayTitle
                        )
                    } label: {
                        Label("Subscribe", systemImage: "plus.circle")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Subscribe"))
                    .accessibilityHint(
                        String(localized: "Opens a feed preview to confirm Subscribe for the recommended podcast")
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}
