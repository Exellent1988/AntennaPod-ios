import SwiftUI
import UIKit

/// Feed-provided `podcast:txt` list — optional purpose label (raw feed string) + text body.
/// Distinct **Copy / Share text purpose**, **Copy / Share text content**, and full-entry **Copy / Share text entry** actions; full-entry Share prefers an http(s) URL. **Open** when the text looks like http(s). Cap + honesty footnote.
/// **Display-only** — no Social / Matrix / special clients. Hidden when none.
struct PodcastTxtListView: View {
    @Environment(\.openURL) private var openURL

    let texts: [PodcastTxt]
    /// Section title (localized by caller).
    var title: String = String(localized: "Text")

    @State private var showCopiedAlert = false
    @State private var copiedAlertMessage = String(localized: "Text entry copied to the pasteboard.")
    @State private var copyFeedbackTick = 0

    private var capped: (shown: [PodcastTxt], truncated: Bool) {
        PodcastTxtDisplay.capped(texts)
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
                    txtRow(entry)
                }

                Text(
                    String(
                        localized: "These text entries come from the feed. Copy, share, or open a URL in the system browser — there is no Social or Matrix client."
                    )
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityLabel(
                    String(
                        localized: "These text entries come from the feed. Copy, share, or open a URL in the system browser — there is no Social or Matrix client."
                    )
                )

                if result.truncated {
                    Text(String(localized: "Showing first 20 text entries from the feed."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(
                            String(localized: "Showing first 20 text entries from the feed.")
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
        }
    }

    @ViewBuilder
    private func txtRow(_ entry: PodcastTxt) -> some View {
        let purpose = entry.displayPurpose
        let body = entry.displayText ?? entry.text
        let url = entry.openURL
        let a11y: String = {
            var parts: [String] = [String(localized: "Text")]
            if let purpose {
                parts.append(String(localized: "Purpose \(purpose)"))
            }
            parts.append(body)
            return parts.joined(separator: ", ")
        }()

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "text.alignleft")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                if let purpose {
                    Text(purpose)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(a11y)

            Text(body)
                .font(.subheadline)
                .foregroundStyle(purpose == nil ? .primary : .secondary)
                .lineLimit(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)

            HStack(spacing: 12) {
                if let purpose {
                    Button {
                        UIPasteboard.general.string = purpose
                        copiedAlertMessage = String(localized: "Text purpose copied to the pasteboard.")
                        copyFeedbackTick += 1
                        showCopiedAlert = true
                    } label: {
                        Label("Copy text purpose", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy text purpose"))
                    .accessibilityHint(
                        String(localized: "Copies the exact feed-provided text purpose to the pasteboard")
                    )

                    ShareLink(item: purpose) {
                        Label("Share text purpose", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share text purpose"))
                    .accessibilityHint(
                        String(localized: "Shares the exact feed-provided text purpose as plain text")
                    )
                }

                Button {
                    UIPasteboard.general.string = body
                    copiedAlertMessage = String(localized: "Text content copied to the pasteboard.")
                    copyFeedbackTick += 1
                    showCopiedAlert = true
                } label: {
                    Label("Copy text content", systemImage: "doc.on.doc")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Copy text content"))
                .accessibilityHint(
                    String(localized: "Copies the exact displayed feed text content to the pasteboard")
                )

                ShareLink(item: body) {
                    Label("Share text content", systemImage: "square.and.arrow.up")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Share text content"))
                .accessibilityHint(
                    String(localized: "Shares the exact displayed feed text content as plain text")
                )

                Button {
                    UIPasteboard.general.string = PodcastTxtDisplay.copyText(entry)
                    copiedAlertMessage = String(localized: "Text entry copied to the pasteboard.")
                    copyFeedbackTick += 1
                    showCopiedAlert = true
                } label: {
                    Label("Copy text entry", systemImage: "doc.on.doc")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Copy text entry"))
                .accessibilityHint(
                    String(localized: "Copies the exact displayed feed text entry, including its purpose when present, to the pasteboard")
                )

                let copyText = PodcastTxtDisplay.copyText(entry)
                if !copyText.isEmpty {
                    Group {
                        if let url {
                            ShareLink(item: url) {
                                Label("Share text entry", systemImage: "square.and.arrow.up")
                                    .font(.subheadline)
                            }
                        } else {
                            ShareLink(item: copyText) {
                                Label("Share text entry", systemImage: "square.and.arrow.up")
                                    .font(.subheadline)
                            }
                        }
                    }
                    .accessibilityLabel(String(localized: "Share text entry"))
                    .accessibilityHint(
                        String(
                            localized: "Shares the exact displayed feed text entry as plain text, preferring its parseable http(s) URL when available"
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
                        String(localized: "Opens the URL from the feed text entry in the system browser")
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}
