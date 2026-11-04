import SwiftUI
import UIKit

/// Feed-provided channel `podcast:publisher` / nested `podcast:remoteItem` list.
/// Publisher name (title) + url/guid when present; **Open** http(s) feed URL; **Copy** / **Share**; **Subscribe** via
/// existing `FeedPreviewRequest` preview when feedUrl is http(s). Cap 1 + honesty footnote.
/// **Display-only** — never invent publishers; no Podcast Index GUID resolution.
/// GUID-only → Copy (no Open / Subscribe). Hidden when none.
struct PodcastPublisherListView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: PodcastStore

    let items: [PodcastRemoteItem]
    /// Section title (localized by caller).
    var title: String = String(localized: "Publisher")

    @State private var showCopiedAlert = false
    @State private var copiedAlertMessage = String(localized: "Publisher details copied to the pasteboard.")
    @State private var copyFeedbackTick = 0
    @State private var previewRequest: FeedPreviewRequest?

    private var capped: (shown: [PodcastRemoteItem], truncated: Bool) {
        PodcastPublisherDisplay.capped(items)
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
                    publisherRow(entry)
                }

                Text(
                    String(
                        localized: "This publisher comes from the feed (podcast:publisher). Open or copy a feed URL, or preview Subscribe when a URL is present — this app does not invent publishers or resolve Podcast Index GUIDs."
                    )
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityLabel(
                    String(
                        localized: "This publisher comes from the feed (podcast:publisher). Open or copy a feed URL, or preview Subscribe when a URL is present — this app does not invent publishers or resolve Podcast Index GUIDs."
                    )
                )

                if result.truncated {
                    Text(String(localized: "Showing first publisher from the feed."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(
                            String(localized: "Showing first publisher from the feed.")
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
    private func publisherRow(_ entry: PodcastRemoteItem) -> some View {
        let label = entry.primaryLabel ?? ""
        let url = entry.openURL
        let copyText = PodcastPublisherDisplay.copyText(entry)
        let guid = entry.displayFeedGuid
        let itemGuid = entry.displayItemGuid
        let a11y: String = {
            var parts: [String] = [String(localized: "Publisher")]
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
                Image(systemName: "building.2")
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
                        copiedAlertMessage = String(localized: "Publisher title copied to the pasteboard.")
                        copyFeedbackTick += 1
                        showCopiedAlert = true
                    } label: {
                        Label("Copy publisher title", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy publisher title"))
                    .accessibilityHint(
                        String(localized: "Copies the exact feed-provided publisher title as plain text")
                    )

                    ShareLink(item: title) {
                        Label("Share publisher title", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share publisher title"))
                    .accessibilityHint(
                        String(localized: "Shares the exact feed-provided publisher title as plain text")
                    )
                }

                if let guid {
                    Button {
                        UIPasteboard.general.string = guid
                        copiedAlertMessage = String(localized: "Publisher feed GUID copied to the pasteboard.")
                        copyFeedbackTick += 1
                        showCopiedAlert = true
                    } label: {
                        Label("Copy publisher feed GUID", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy publisher feed GUID"))
                    .accessibilityHint(
                        String(localized: "Copies the exact feed-provided publisher feed GUID as plain text")
                    )

                    ShareLink(item: guid, subject: Text(label)) {
                        Label("Share publisher feed GUID", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share publisher feed GUID"))
                    .accessibilityHint(
                        String(localized: "Shares the exact feed-provided publisher feed GUID as plain text")
                    )
                }

                if let itemGuid {
                    Button {
                        UIPasteboard.general.string = itemGuid
                        copiedAlertMessage = String(localized: "Publisher item GUID copied to the pasteboard.")
                        copyFeedbackTick += 1
                        showCopiedAlert = true
                    } label: {
                        Label("Copy publisher item GUID", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy publisher item GUID"))
                    .accessibilityHint(
                        String(localized: "Copies the exact feed-provided publisher item GUID as plain text")
                    )

                    ShareLink(item: itemGuid, subject: Text(label)) {
                        Label("Share publisher item GUID", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share publisher item GUID"))
                    .accessibilityHint(
                        String(localized: "Shares the exact feed-provided publisher item GUID as plain text")
                    )
                }

                if let medium = entry.displayMedium {
                    Button {
                        UIPasteboard.general.string = medium
                        copiedAlertMessage = String(localized: "Publisher medium copied to the pasteboard.")
                        copyFeedbackTick += 1
                        showCopiedAlert = true
                    } label: {
                        Label("Copy publisher medium", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy publisher medium"))
                    .accessibilityHint(String(localized: "Copies the exact feed-provided publisher medium as plain text"))

                    ShareLink(item: medium, subject: Text(label)) {
                        Label("Share publisher medium", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share publisher medium"))
                    .accessibilityHint(String(localized: "Shares the exact feed-provided publisher medium as plain text"))
                }

                Button {
                    UIPasteboard.general.string = PodcastPublisherDisplay.copyText(entry)
                    copiedAlertMessage = String(localized: "Publisher details copied to the pasteboard.")
                    copyFeedbackTick += 1
                    showCopiedAlert = true
                } label: {
                    Label("Copy publisher details", systemImage: "doc.on.doc")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Copy publisher details"))
                .accessibilityHint(
                    String(localized: "Copies the displayed publisher title, feed URL, feed GUID, and item GUID to the pasteboard")
                )

                if !copyText.isEmpty {
                    Group {
                        if let url {
                            ShareLink(item: url) {
                                Label("Share publisher details", systemImage: "square.and.arrow.up")
                                    .font(.subheadline)
                            }
                        } else {
                            ShareLink(item: copyText) {
                                Label("Share publisher details", systemImage: "square.and.arrow.up")
                                    .font(.subheadline)
                            }
                        }
                    }
                    .accessibilityLabel(String(localized: "Share publisher details"))
                    .accessibilityHint(
                        String(
                            localized: "Shares the displayed publisher feed URL when it is a parseable http(s) URL; otherwise shares the same feed-provided text as Copy publisher details"
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
                        String(localized: "Opens the publisher feed URL in the system browser")
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
                        String(localized: "Opens a feed preview to confirm Subscribe for the publisher feed")
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}
