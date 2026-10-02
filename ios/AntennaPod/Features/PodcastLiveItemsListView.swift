import SwiftUI
import UIKit

/// Feed-provided `podcast:liveItem` list: status + title + start/end + Copy / Share / Open link / contentLinks.
/// Caps at `PodcastLiveItemDisplay.displayCap` with an honesty footnote when truncated.
/// **Display-only** — does **not** play live enclosures, open chat, record, or process payments.
/// Copy / Share / Open actions use only feed-provided http(s) link / contentLink URLs.
struct PodcastLiveItemsListView: View {
    @Environment(\.openURL) private var openURL

    @State private var showCopiedAlert = false
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
                Text(String(localized: "Live item URL copied to the pasteboard."))
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
        let linkURL = item.linkURL
        let contentLinks = item.openableContentLinks

        let a11yLabel: String = {
            var parts = [statusText]
            if let titleText { parts.append(titleText) }
            parts.append(String(localized: "Starts \(startText)"))
            if let endText { parts.append(String(localized: "Ends \(endText)")) }
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
                Text(String(localized: "Starts \(startText)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                if let endText {
                    Text(String(localized: "Ends \(endText)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }

            if let url = linkURL {
                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = url.absoluteString
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
