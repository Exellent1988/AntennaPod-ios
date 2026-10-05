import SwiftUI
import UIKit

/// Simple feed-provided `podcast:socialInteract` list: Copy / Share the exact protocol, account ID, and same http(s) URI; Discuss opens it.
/// Priority-sorted (lower = higher); caps at `PodcastSocialInteractDisplay.displayCap` with honesty footnote.
/// **openURL / Share / Copy only** — no in-app Fediverse client, no posting / API. Hidden when none / disabled-only.
struct PodcastSocialInteractListView: View {
    @Environment(\.openURL) private var openURL

    @State private var showCopiedAlert = false
    @State private var showProtocolCopiedAlert = false
    @State private var showAccountCopiedAlert = false
    @State private var copyFeedbackTick = 0
    @State private var copyProtocolFeedbackTick = 0
    @State private var copyAccountFeedbackTick = 0

    let socialInteracts: [PodcastSocialInteract]
    /// Section title (localized by caller).
    var title: String = String(localized: "Discuss")

    private var capped: (shown: [PodcastSocialInteract], truncated: Bool) {
        PodcastSocialInteractDisplay.capped(socialInteracts)
    }

    var body: some View {
        let result = capped
        if !result.shown.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)

                ForEach(Array(result.shown.enumerated()), id: \.offset) { _, interact in
                    socialRow(interact)
                }

                if result.truncated {
                    Text(String(localized: "Showing first 20 discussion links from the feed."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(String(localized: "Showing first 20 discussion links from the feed."))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .alert(String(localized: "Copied"), isPresented: $showCopiedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(String(localized: "Discuss URL copied to the pasteboard."))
            }
            .alert(String(localized: "Copied"), isPresented: $showProtocolCopiedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(String(localized: "Discuss protocol copied to the pasteboard."))
            }
            .alert(String(localized: "Copied"), isPresented: $showAccountCopiedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(String(localized: "Discuss account ID copied to the pasteboard."))
            }
            .sensoryFeedback(.success, trigger: copyFeedbackTick)
            .sensoryFeedback(.success, trigger: copyProtocolFeedbackTick)
            .sensoryFeedback(.success, trigger: copyAccountFeedbackTick)
        }
    }

    @ViewBuilder
    private func socialRow(_ interact: PodcastSocialInteract) -> some View {
        let proto = interact.displayProtocol ?? interact.protocolName
        let account = interact.displayAccountId
        let url = interact.discussionURL

        let a11yLabel: String = {
            var parts = [String(localized: "Discuss")]
            parts.append(String(localized: "Protocol \(proto)"))
            if let account { parts.append(String(localized: "Account \(account)")) }
            return parts.joined(separator: ", ")
        }()

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(proto)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                if let account {
                    Text(account)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(a11yLabel)

            if let account {
                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = account
                        copyAccountFeedbackTick += 1
                        showAccountCopiedAlert = true
                    } label: {
                        Label("Copy discuss account ID", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy discuss account ID"))
                    .accessibilityHint(
                        String(localized: "Copies the displayed feed-provided discussion account ID as plain text; does not post as you")
                    )

                    ShareLink(item: account) {
                        Label("Share discuss account ID", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share discuss account ID"))
                    .accessibilityHint(
                        String(localized: "Shares the displayed feed-provided discussion account ID as plain text; does not post as you")
                    )
                }
            }

            if let url {
                VStack(alignment: .leading, spacing: 4) {
                    if let protocolText = interact.displayProtocol {
                        HStack(spacing: 12) {
                            Button {
                                UIPasteboard.general.string = protocolText
                                copyProtocolFeedbackTick += 1
                                showProtocolCopiedAlert = true
                            } label: {
                                Label("Copy discuss protocol", systemImage: "doc.on.doc")
                                    .font(.subheadline)
                            }
                            .accessibilityLabel(String(localized: "Copy discuss protocol"))
                            .accessibilityHint(
                                String(localized: "Copies the displayed feed-provided discussion protocol to the pasteboard; does not post as you")
                            )

                            ShareLink(item: protocolText) {
                                Label("Share discuss protocol", systemImage: "square.and.arrow.up")
                                    .font(.subheadline)
                            }
                            .accessibilityLabel(String(localized: "Share discuss protocol"))
                            .accessibilityHint(
                                String(localized: "Shares the displayed feed-provided discussion protocol as plain text; does not post as you")
                            )
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            UIPasteboard.general.string = url.absoluteString
                            copyFeedbackTick += 1
                            showCopiedAlert = true
                        } label: {
                            Label("Copy discuss URL", systemImage: "doc.on.doc")
                                .font(.subheadline)
                        }
                        .accessibilityLabel(String(localized: "Copy discuss URL"))
                        .accessibilityHint(
                            String(localized: "Copies the feed-provided discussion URL to the pasteboard. No confirmation. Does not post as you. Never uses the feed RSS URL or the podcast website. Distinct from Discuss, Share discuss URL, and Copy feed URL. Does not open a browser, subscribe, or download.")
                        )

                        ShareLink(item: url) {
                            Label("Share discuss URL", systemImage: "square.and.arrow.up")
                                .font(.subheadline)
                        }
                        .accessibilityLabel(String(localized: "Share discuss URL"))
                        .accessibilityHint(
                            String(localized: "Opens the system share sheet with the feed-provided discussion URL. Does not post as you. Never uses the feed RSS URL or the podcast website. Distinct from Discuss, Copy discuss URL, and Share feed URL. Sharing is your choice and does not subscribe or download.")
                        )

                        Button {
                            openURL(url)
                        } label: {
                            Label("Discuss", systemImage: "safari")
                                .font(.subheadline)
                        }
                        .accessibilityLabel(String(localized: "Discuss"))
                        .accessibilityHint(String(localized: "Opens the feed-provided discussion http(s) link in the system browser — not an in-app WebView. No confirmation. Does not post as you. Never uses the feed RSS URL or the podcast website. Distinct from Copy discuss URL, Share discuss URL, and Open podcast website. Does not subscribe, download, or change playback."))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}
