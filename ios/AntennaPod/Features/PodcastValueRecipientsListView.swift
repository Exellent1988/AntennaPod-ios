import SwiftUI
import UIKit

/// Feed-provided `podcast:value` / `valueRecipient` list — **Value / Support creators** metadata only.
/// Shows name, type/method, split % when known. When a feed name is shown, distinct Copy / Share value recipient name
/// uses that exact text (separate from details + address). When type/method caption is shown, distinct Copy / Share
/// value type/method uses that exact caption (separate from name, details, address). When the split label is shown,
/// distinct Copy / Share value split uses that exact displayed string (separate from name, type/method, fee, details,
/// address). When the Fee capsule is shown (`isFee`), distinct Copy / Share value fee uses that exact displayed Fee
/// label (separate from name, type/method, split, details, address; hide when not a fee — never invent Fee).
/// When a feed address is shown, distinct Copy / Share value address uses that exact displayed
/// address (Copy always pastes the raw displayed string; Share prefers parseable http(s) URL when
/// available, otherwise the same raw address; Open in browser for http(s) unchanged; hide when
/// missing — never invent).
/// **Does not send Lightning / wallet payments** — informational display only. Cap + honesty footnote.
struct PodcastValueRecipientsListView: View {
    @Environment(\.openURL) private var openURL

    let values: [PodcastValue]
    /// Section title (localized by caller).
    var title: String = String(localized: "Value / Support creators")

    @State private var showCopiedAlert = false
    @State private var copiedMessage = String(localized: "Address copied to the pasteboard.")
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
                Text(copiedMessage)
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
        let feeLabel = String(localized: "Fee")
        let typeMethodCaption = row.typeMethodCaption
        let hasTypeMethodCaption = !typeMethodCaption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let detailsText: String = {
            var parts: [String] = []
            if let name { parts.append(name) }
            if hasTypeMethodCaption { parts.append(typeMethodCaption) }
            parts.append(splitLabel)
            if row.isFee { parts.append(feeLabel) }
            return parts.joined(separator: " · ")
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
                if hasTypeMethodCaption {
                    Text(typeMethodCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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

            if let name {
                HStack(spacing: 12) {
                    Button {
                        copyToPasteboard(
                            name,
                            confirmation: String(localized: "Value recipient name copied to the pasteboard.")
                        )
                    } label: {
                        Label("Copy value recipient name", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy value recipient name"))
                    .accessibilityHint(
                        String(
                            localized: "Copies the exact displayed value recipient name as plain text; this app does not send payments."
                        )
                    )

                    ShareLink(item: name) {
                        Label("Share value recipient name", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share value recipient name"))
                    .accessibilityHint(
                        String(
                            localized: "Shares the exact displayed value recipient name as plain text; this app does not send payments."
                        )
                    )
                }
            }

            if hasTypeMethodCaption {
                HStack(spacing: 12) {
                    Button {
                        copyToPasteboard(
                            typeMethodCaption,
                            confirmation: String(localized: "Value type/method copied to the pasteboard.")
                        )
                    } label: {
                        Label("Copy value type/method", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy value type/method"))
                    .accessibilityHint(
                        String(
                            localized: "Copies the exact displayed value type/method caption as plain text; this app does not send payments."
                        )
                    )

                    ShareLink(item: typeMethodCaption) {
                        Label("Share value type/method", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share value type/method"))
                    .accessibilityHint(
                        String(
                            localized: "Shares the exact displayed value type/method caption as plain text; this app does not send payments."
                        )
                    )
                }
            }

            HStack(spacing: 12) {
                Button {
                    copyToPasteboard(
                        splitLabel,
                        confirmation: String(localized: "Value split copied to the pasteboard.")
                    )
                } label: {
                    Label("Copy value split", systemImage: "doc.on.doc")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Copy value split"))
                .accessibilityHint(
                    String(
                        localized: "Copies the exact displayed value split as plain text; this app does not send payments."
                    )
                )

                ShareLink(item: splitLabel) {
                    Label("Share value split", systemImage: "square.and.arrow.up")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Share value split"))
                .accessibilityHint(
                    String(
                        localized: "Shares the exact displayed value split as plain text; this app does not send payments."
                    )
                )
            }

            if row.isFee {
                HStack(spacing: 12) {
                    Button {
                        copyToPasteboard(
                            feeLabel,
                            confirmation: String(localized: "Value fee copied to the pasteboard.")
                        )
                    } label: {
                        Label("Copy value fee", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy value fee"))
                    .accessibilityHint(
                        String(
                            localized: "Copies the exact displayed Fee label as plain text; this app does not send payments."
                        )
                    )

                    ShareLink(item: feeLabel) {
                        Label("Share value fee", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share value fee"))
                    .accessibilityHint(
                        String(
                            localized: "Shares the exact displayed Fee label as plain text; this app does not send payments."
                        )
                    )
                }
            }

            HStack(spacing: 12) {
                Button {
                    copyToPasteboard(
                        detailsText,
                        confirmation: String(localized: "Value recipient details copied to the pasteboard.")
                    )
                } label: {
                    Label("Copy value recipient details", systemImage: "doc.on.doc")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Copy value recipient details"))
                .accessibilityHint(
                    String(
                        localized: "Copies the displayed value recipient name, type, method, split, and fee metadata as plain text; this app does not send payments."
                    )
                )

                ShareLink(item: detailsText) {
                    Label("Share value recipient details", systemImage: "square.and.arrow.up")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Share value recipient details"))
                .accessibilityHint(
                    String(
                        localized: "Shares the displayed value recipient name, type, method, split, and fee metadata as plain text; this app does not send payments."
                    )
                )
            }

            if let address = row.displayAddress {
                Text(address)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .accessibilityLabel(String(localized: "Address \(address)"))

                HStack(spacing: 12) {
                    Button {
                        copyToPasteboard(
                            address,
                            confirmation: String(localized: "Value address copied to the pasteboard.")
                        )
                    } label: {
                        Label("Copy value address", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy value address"))
                    .accessibilityHint(
                        String(
                            localized: "Copies the exact displayed value recipient address as plain text; this app does not send payments."
                        )
                    )

                    Group {
                        if let url = row.browserURL {
                            ShareLink(item: url) {
                                Label("Share value address", systemImage: "square.and.arrow.up")
                                    .font(.subheadline)
                            }
                        } else {
                            ShareLink(item: address) {
                                Label("Share value address", systemImage: "square.and.arrow.up")
                                    .font(.subheadline)
                            }
                        }
                    }
                    .accessibilityLabel(String(localized: "Share value address"))
                    .accessibilityHint(
                        String(
                            localized: "Shares the feed-provided http(s) value address URL when available; otherwise shares the same raw value address as Copy. This app does not send payments."
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

    private func copyToPasteboard(_ string: String, confirmation: String) {
        UIPasteboard.general.string = string
        copiedMessage = confirmation
        copyFeedbackTick += 1
        showCopiedAlert = true
    }
}
