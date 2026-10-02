import SwiftUI
import UIKit

/// Feed-provided `podcast:liveItem` list: status + title + start/end + Copy / Share / Open link / contentLinks.
/// Caps at `PodcastLiveItemDisplay.displayCap` with an honesty footnote when truncated.
/// **Display-only** — does **not** play live enclosures, open chat, record, or process payments.
/// Copy / Share metadata and Open / Copy / Share link actions use only displayed or feed-provided values.
/// When the status capsule is shown, distinct **Copy / Share live item status** use the exact displayed status string.
/// When Starts / Ends captions are shown, distinct **Copy / Share live item start** (always) and **end** (when end present) use those exact caption strings — never invent an end.
struct PodcastLiveItemsListView: View {
    @Environment(\.openURL) private var openURL

    @State private var showCopiedAlert = false
    @State private var copiedAlertMessage = String(localized: "Live item URL copied to the pasteboard.")
    @State private var copyFeedbackTick = 0

    let liveItems: [PodcastLiveItem]
    /// Section title (localized by caller).
    var title: String = String(localized: "Live")

    private var capped: (shown: [PodcastLiveItem], truncated: Bool) {
        PodcastLiveItemDisplay.capped(liveItems)
    }

    var body: some View {
        let result = capped
        if !result.shown.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)

                ForEach(Array(result.shown.enumerated()), id: \.offset) { _, item in
                    liveItemRow(item)
                }

                Text(String(localized: "This app shows live item schedule and links only. It does not play live streams, record, or open chat."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(String(localized: "This app shows live item schedule and links only. It does not play live streams, record, or open chat."))

                if result.truncated {
                    Text(String(localized: "Showing first 20 live items from the feed."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(String(localized: "Showing first 20 live items from the feed."))
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
        }
    }

    @ViewBuilder
    private func liveItemRow(_ item: PodcastLiveItem) -> some View {
        let statusText = PodcastLiveItemDisplay.statusLabel(item.status)
        let titleText = item.displayTitle
        let startText = PodcastLiveItemDisplay.formatTimestamp(raw: item.start, epochMs: item.startEpochMs)
        let endText: String? = {
            guard let end = item.end else { return nil }
            return PodcastLiveItemDisplay.formatTimestamp(raw: end, epochMs: item.endEpochMs)
        }()
        // Exact displayed captions — Copy/Share must match these strings; never invent an end.
        let startCaption = String(localized: "Starts \(startText)")
        let endCaption: String? = endText.map { String(localized: "Ends \($0)") }
        var detailLines = [statusText]
        if let titleText { detailLines.append(titleText) }
        detailLines.append(startCaption)
        if let endCaption { detailLines.append(endCaption) }
        let detailsText = detailLines.joined(separator: "\n")
        let linkURL = item.linkURL
        let contentLinks = item.openableContentLinks

        let a11yLabel: String = {
            var parts = [statusText]
            if let titleText { parts.append(titleText) }
            parts.append(startCaption)
            if let endCaption { parts.append(endCaption) }
            if linkURL != nil { parts.append(String(localized: "Has live page link from the feed")) }
            if !contentLinks.isEmpty {
                parts.append(String(localized: "Has \(contentLinks.count) content links from the feed"))
            }
            return parts.joined(separator: ", ")
        }()

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusBackground(item.status), in: Capsule())
                    .foregroundStyle(statusForeground(item.status))
                    .accessibilityHidden(true)

                if let titleText {
                    Text(titleText)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(a11yLabel)

            VStack(alignment: .leading, spacing: 2) {
                Text(startCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                if let endCaption {
                    Text(endCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }

            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = statusText
                    copiedAlertMessage = String(localized: "Live item status copied to the pasteboard.")
                    copyFeedbackTick += 1
                    showCopiedAlert = true
                } label: {
                    Label("Copy live item status", systemImage: "doc.on.doc")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Copy live item status"))
                .accessibilityHint(
                    String(localized: "Copies the exact displayed live item status as plain text")
                )

                ShareLink(item: statusText) {
                    Label("Share live item status", systemImage: "square.and.arrow.up")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Share live item status"))
                .accessibilityHint(
                    String(localized: "Shares the exact displayed live item status as plain text")
                )
            }

            if let titleText {
                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = titleText
                        copiedAlertMessage = String(localized: "Live item title copied to the pasteboard.")
                        copyFeedbackTick += 1
                        showCopiedAlert = true
                    } label: {
                        Label("Copy live item title", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy live item title"))
                    .accessibilityHint(
                        String(localized: "Copies the exact feed-provided live item title as plain text")
                    )

                    ShareLink(item: titleText) {
                        Label("Share live item title", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share live item title"))
                    .accessibilityHint(
                        String(localized: "Shares the exact feed-provided live item title as plain text")
                    )
                }
            }

            // Exact displayed Starts caption — always shown; distinct from details/status/title.
            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = startCaption
                    copiedAlertMessage = String(localized: "Live item start copied to the pasteboard.")
                    copyFeedbackTick += 1
                    showCopiedAlert = true
                } label: {
                    Label("Copy live item start", systemImage: "doc.on.doc")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Copy live item start"))
                .accessibilityHint(
                    String(localized: "Copies the exact displayed Starts caption as plain text")
                )

                ShareLink(item: startCaption) {
                    Label("Share live item start", systemImage: "square.and.arrow.up")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Share live item start"))
                .accessibilityHint(
                    String(localized: "Shares the exact displayed Starts caption as plain text")
                )
            }

            // Exact displayed Ends caption — only when endCaption is non-nil; never invent an end.
            if let endCaption {
                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = endCaption
                        copiedAlertMessage = String(localized: "Live item end copied to the pasteboard.")
                        copyFeedbackTick += 1
                        showCopiedAlert = true
                    } label: {
                        Label("Copy live item end", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy live item end"))
                    .accessibilityHint(
                        String(localized: "Copies the exact displayed Ends caption as plain text")
                    )

                    ShareLink(item: endCaption) {
                        Label("Share live item end", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share live item end"))
                    .accessibilityHint(
                        String(localized: "Shares the exact displayed Ends caption as plain text")
                    )
                }
            }

            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = detailsText
                    copiedAlertMessage = String(localized: "Live item details copied to the pasteboard.")
                    copyFeedbackTick += 1
                    showCopiedAlert = true
                } label: {
                    Label("Copy live item details", systemImage: "doc.on.doc")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Copy live item details"))
                .accessibilityHint(
                    String(localized: "Copies the displayed live item status, optional title, and start/end times to the pasteboard")
                )

                ShareLink(item: detailsText) {
                    Label("Share live item details", systemImage: "square.and.arrow.up")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Share live item details"))
                .accessibilityHint(
                    String(localized: "Shares the displayed live item status, optional title, and start/end times as plain text")
                )
            }

            if let url = linkURL {
                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = url.absoluteString
                        copiedAlertMessage = String(localized: "Live item URL copied to the pasteboard.")
                        copyFeedbackTick += 1
                        showCopiedAlert = true
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy live page link"))
                    .accessibilityHint(
                        String(localized: "Copies the feed-provided live page URL to the pasteboard")
                    )

                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share live page link"))
                    .accessibilityHint(
                        String(localized: "Shares the feed-provided live page URL")
                    )

                    Button {
                        openURL(url)
                    } label: {
                        Label("Open live page", systemImage: "safari")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Open live page"))
                    .accessibilityHint(String(localized: "Opens the live item page link from the feed in the system browser"))
                }
            }

            ForEach(Array(contentLinks.enumerated()), id: \.offset) { _, contentLink in
                if let url = contentLink.browserURL {
                    let label = contentLink.displayLabel ?? String(localized: "Open content link")
                    if let feedLabel = contentLink.displayLabel {
                        HStack(spacing: 12) {
                            Button {
                                UIPasteboard.general.string = feedLabel
                                copiedAlertMessage = String(localized: "Content link label copied to the pasteboard.")
                                copyFeedbackTick += 1
                                showCopiedAlert = true
                            } label: {
                                Label("Copy content link label", systemImage: "doc.on.doc")
                                    .font(.subheadline)
                            }
                            .accessibilityLabel(String(localized: "Copy content link label"))
                            .accessibilityHint(
                                String(localized: "Copies the exact feed-provided content link label shown above as plain text")
                            )

                            ShareLink(item: feedLabel) {
                                Label("Share content link label", systemImage: "square.and.arrow.up")
                                    .font(.subheadline)
                            }
                            .accessibilityLabel(String(localized: "Share content link label"))
                            .accessibilityHint(
                                String(localized: "Shares the exact feed-provided content link label shown above as plain text")
                            )
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            UIPasteboard.general.string = url.absoluteString
                            copyFeedbackTick += 1
                            showCopiedAlert = true
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.subheadline)
                        }
                        .accessibilityLabel(String(localized: "Copy content link"))
                        .accessibilityHint(
                            String(localized: "Copies the feed-provided content link URL to the pasteboard")
                        )

                        ShareLink(item: url) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .font(.subheadline)
                        }
                        .accessibilityLabel(String(localized: "Share content link"))
                        .accessibilityHint(
                            String(localized: "Shares the feed-provided content link URL")
                        )

                        Button {
                            openURL(url)
                        } label: {
                            Label(label, systemImage: "link")
                                .font(.subheadline)
                        }
                        .accessibilityLabel(label)
                        .accessibilityHint(String(localized: "Opens a content link from the feed in the system browser"))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private func statusBackground(_ status: PodcastLiveItemStatus) -> Color {
        switch status {
        case .live: return Color.red.opacity(0.18)
        case .pending: return Color.orange.opacity(0.18)
        case .ended: return Color.secondary.opacity(0.14)
        }
    }

    private func statusForeground(_ status: PodcastLiveItemStatus) -> Color {
        switch status {
        case .live: return .red
        case .pending: return .orange
        case .ended: return .secondary
        }
    }
}
