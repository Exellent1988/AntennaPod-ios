import SwiftUI
import UIKit

/// Feed-provided `podcast:value` / `valueRecipient` list — **Value / Support creators** metadata only.
/// Shows name, type/method, split % when known. http(s) address → Share / Open in browser; otherwise Copy / Share address.
/// **Does not send Lightning / wallet payments** — informational display only. Cap + honesty footnote.
struct PodcastValueRecipientsListView: View {
    @Environment(\.openURL) private var openURL

    let values: [PodcastValue]
    /// Section title (localized by caller).
    var title: String = String(localized: "Value / Support creators")

    @State private var showCopiedAlert = false
    @State private var copyFeedbackTick = 0

    private var capped: (shown: [PodcastValueRecipientRow], truncated: Bool) {
        PodcastValueDisplay.capped(values)
    }

    var body: some View {
        let result = capped
        if !result.shown.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)

                ForEach(Array(result.shown.enumerated()), id: \.offset) { _, row in
                    recipientRow(row)
                }

                Text(String(localized: "This app does not send payments. Addresses are shown for information only."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(
                        String(localized: "This app does not send payments. Addresses are shown for information only.")
                    )

                if result.truncated {
                    Text(String(localized: "Showing first 20 value recipients from the feed."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(String(localized: "Showing first 20 value recipients from the feed."))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .alert(String(localized: "Copied"), isPresented: $showCopiedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(String(localized: "Address copied to the pasteboard."))
            }
            .sensoryFeedback(.success, trigger: copyFeedbackTick)
        }
    }

    @ViewBuilder
    private func recipientRow(_ row: PodcastValueRecipientRow) -> some View {
        let name = row.displayName
        let rType = row.displayRecipientType ?? row.recipient.type
        let splitLabel: String = {
            if let pct = row.splitPercent {
                return String(localized: "Split \(pct) percent")
            }
            return String(localized: "Split shares \(row.split)")
        }()
        let a11y: String = {
            var parts: [String] = []
            if let name { parts.append(name) }
            parts.append(String(localized: "Type \(rType)"))
            parts.append(String(localized: "Method \(row.valueMethod)"))
            parts.append(String(localized: "Value layer \(row.valueType)"))
            parts.append(splitLabel)
            if row.isFee {
                parts.append(String(localized: "Fee recipient"))
            }
            return parts.joined(separator: ", ")
        }()

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "heart.text.square")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                if let name {
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
                Text(row.typeMethodCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(splitLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if row.isFee {
                    Text(String(localized: "Fee"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(a11y)

            if let address = row.displayAddress {
                Text(address)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .accessibilityLabel(String(localized: "Address \(address)"))

                HStack(spacing: 12) {
                    if row.browserURL == nil {
                        Button {
                            UIPasteboard.general.string = address
                            copyFeedbackTick += 1
                            showCopiedAlert = true
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.subheadline)
                        }
                        .accessibilityLabel(String(localized: "Copy"))
                        .accessibilityHint(
                            String(localized: "Copies the recipient address to the pasteboard. This app does not send payments.")
                        )
                    }

                    Group {
                        if let url = row.browserURL {
                            ShareLink(item: url) {
                                Label("Share", systemImage: "square.and.arrow.up")
                                    .font(.subheadline)
                            }
                        } else {
                            ShareLink(item: address) {
                                Label("Share", systemImage: "square.and.arrow.up")
                                    .font(.subheadline)
                            }
                        }
                    }
                    .accessibilityLabel(String(localized: "Share recipient address"))
                    .accessibilityHint(
                        String(
                            localized: "Shares the feed-provided http(s) recipient URL when available; otherwise shares the same raw recipient address as Copy. This app does not send payments."
                        )
                    )

                    if let url = row.browserURL {
                        Button {
                            openURL(url)
                        } label: {
                            Label("Open in browser", systemImage: "safari")
                                .font(.subheadline)
                        }
                        .accessibilityLabel(String(localized: "Open in browser"))
                        .accessibilityHint(
                            String(localized: "Opens the recipient page from the feed in the system browser")
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}
