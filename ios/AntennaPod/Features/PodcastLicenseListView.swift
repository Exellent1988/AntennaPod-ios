import SwiftUI
import UIKit

/// Feed-provided `podcast:license` list — license text (+ optional url attribute).
/// When license text is shown: distinct **Copy / Share license text**.
/// When a feed url is shown: distinct **Copy / Share license URL** for that exact
/// displayed string (Copy always pastes the raw displayed URL string; Share prefers
/// parseable http(s) when available, otherwise the same raw string; **Open** http(s)
/// unchanged; hide when missing — never invent).
/// **Display-only** — no DRM enforcement. Hidden when none.
struct PodcastLicenseListView: View {
    @Environment(\.openURL) private var openURL

    let licenses: [PodcastLicense]
    /// Section title (localized by caller).
    var title: String = String(localized: "License")

    @State private var showCopiedAlert = false
    @State private var copiedAlertMessage = String(localized: "License copied to the pasteboard.")
    @State private var copyFeedbackTick = 0

    private var capped: (shown: [PodcastLicense], truncated: Bool) {
        PodcastLicenseDisplay.capped(licenses)
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
                    licenseRow(entry)
                }

                Text(
                    String(
                        localized: "These licenses come from the feed. Display only — this app does not enforce DRM or license terms."
                    )
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityLabel(
                    String(
                        localized: "These licenses come from the feed. Display only — this app does not enforce DRM or license terms."
                    )
                )

                if result.truncated {
                    Text(String(localized: "Showing first 5 licenses from the feed."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(
                            String(localized: "Showing first 5 licenses from the feed.")
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
    private func licenseRow(_ entry: PodcastLicense) -> some View {
        let body = entry.displayText
        let urlString = entry.displayUrlString
        let browserURL = entry.openURL
        let a11y: String = {
            var parts: [String] = [String(localized: "License")]
            if let body {
                parts.append(body)
            }
            if let urlString {
                parts.append(urlString)
            }
            return parts.joined(separator: ", ")
        }()

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                if let body {
                    Text(body)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                } else if let urlString {
                    Text(urlString)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(a11y)

            if body != nil, let urlString {
                Text(urlString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .accessibilityHidden(true)
            }

            if let body {
                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = body
                        copiedAlertMessage = String(localized: "License text copied to the pasteboard.")
                        copyFeedbackTick += 1
                        showCopiedAlert = true
                    } label: {
                        Label("Copy license text", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy license text"))
                    .accessibilityHint(
                        String(localized: "Copies the exact feed-provided license text shown above as plain text")
                    )

                    ShareLink(item: body) {
                        Label("Share license text", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share license text"))
                    .accessibilityHint(
                        String(localized: "Shares the exact feed-provided license text shown above as plain text")
                    )
                }
            }

            if let urlString {
                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = urlString
                        copiedAlertMessage = String(localized: "License URL copied to the pasteboard.")
                        copyFeedbackTick += 1
                        showCopiedAlert = true
                    } label: {
                        Label("Copy license URL", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy license URL"))
                    .accessibilityHint(
                        String(
                            localized: "Copies the exact feed-provided license URL shown above as plain text. Display only — this app does not enforce DRM."
                        )
                    )

                    Group {
                        if let browserURL {
                            ShareLink(item: browserURL) {
                                Label("Share license URL", systemImage: "square.and.arrow.up")
                                    .font(.subheadline)
                            }
                        } else {
                            ShareLink(item: urlString) {
                                Label("Share license URL", systemImage: "square.and.arrow.up")
                                    .font(.subheadline)
                            }
                        }
                    }
                    .accessibilityLabel(String(localized: "Share license URL"))
                    .accessibilityHint(
                        String(
                            localized: "Shares the feed-provided http(s) license URL when available; otherwise shares the same raw license URL as Copy. Display only — this app does not enforce DRM."
                        )
                    )

                    if let browserURL {
                        Button {
                            openURL(browserURL)
                        } label: {
                            Label("Open", systemImage: "safari")
                                .font(.subheadline)
                        }
                        .accessibilityLabel(String(localized: "Open"))
                        .accessibilityHint(
                            String(localized: "Opens the license URL in the system browser")
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}
