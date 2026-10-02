import SwiftUI
import UIKit

/// Feed-provided `podcast:images` / `podcast:image` variants — URL + optional width.
/// **Open** http(s) / **Copy** / **Share**; cap + honesty footnote.
/// Does **not** download all variants eagerly (artwork preference picks one URL elsewhere).
/// **Hidden when none.**
struct PodcastImagesListView: View {
    @Environment(\.openURL) private var openURL

    let images: [PodcastImageVariant]
    /// Section title (localized by caller).
    var title: String = String(localized: "Images")

    @State private var showCopiedAlert = false
    @State private var copiedAlertMessage = String(localized: "Image URL copied to the pasteboard.")
    @State private var copyFeedbackTick = 0

    private var capped: (shown: [PodcastImageVariant], truncated: Bool) {
        PodcastImagesDisplay.capped(images)
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
                    imageRow(entry)
                }

                Text(
                    String(
                        localized: "These image URLs come from the feed (podcast:images / podcast:image). Open, copy, or share a link — the app does not download every size. Higher-resolution artwork is preferred for the player when available."
                    )
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityLabel(
                    String(
                        localized: "These image URLs come from the feed (podcast:images / podcast:image). Open, copy, or share a link — the app does not download every size. Higher-resolution artwork is preferred for the player when available."
                    )
                )

                if result.truncated {
                    Text(String(localized: "Showing first 10 image variants from the feed."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(
                            String(localized: "Showing first 10 image variants from the feed.")
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
    private func imageRow(_ entry: PodcastImageVariant) -> some View {
        let urlString = entry.displayURLString ?? entry.url
        let widthLabel = entry.displayWidthLabel
        let purpose = entry.displayPurpose
        let alt = entry.displayAlt
        let open = entry.openURL
        let copyText = PodcastImagesDisplay.copyText(entry)
        let a11y: String = {
            var parts: [String] = [String(localized: "Image")]
            if let widthLabel {
                parts.append(String(localized: "Width \(widthLabel)"))
            }
            if let purpose {
                parts.append(String(localized: "Purpose \(purpose)"))
            }
            if let alt {
                parts.append(alt)
            }
            parts.append(urlString)
            return parts.joined(separator: ", ")
        }()

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                if let widthLabel {
                    Text(widthLabel)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                if let purpose {
                    Text(purpose)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(a11y)

            Text(urlString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)

            if let alt {
                Text(alt)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .accessibilityHidden(true)
            }

            HStack(spacing: 12) {
                if let purpose {
                    Button {
                        UIPasteboard.general.string = purpose
                        copiedAlertMessage = String(localized: "Image purpose copied to the pasteboard.")
                        copyFeedbackTick += 1
                        showCopiedAlert = true
                    } label: {
                        Label("Copy image purpose", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy image purpose"))
                    .accessibilityHint(
                        String(localized: "Copies the exact feed-provided image purpose to the pasteboard")
                    )

                    ShareLink(item: purpose) {
                        Label("Share image purpose", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share image purpose"))
                    .accessibilityHint(
                        String(localized: "Shares the exact feed-provided image purpose as plain text")
                    )
                }

                Button {
                    UIPasteboard.general.string = PodcastImagesDisplay.copyText(entry)
                    copiedAlertMessage = String(localized: "Image URL copied to the pasteboard.")
                    copyFeedbackTick += 1
                    showCopiedAlert = true
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Copy"))
                .accessibilityHint(
                    String(localized: "Copies the image URL from the feed to the pasteboard")
                )

                if !copyText.isEmpty {
                    Group {
                        if let open {
                            ShareLink(item: open) {
                                Label("Share", systemImage: "square.and.arrow.up")
                                    .font(.subheadline)
                            }
                        } else {
                            ShareLink(item: copyText) {
                                Label("Share", systemImage: "square.and.arrow.up")
                                    .font(.subheadline)
                            }
                        }
                    }
                    .accessibilityLabel(String(localized: "Share"))
                    .accessibilityHint(
                        String(
                            localized: "Shares the image URL when it is a parseable http(s) URL; otherwise shares the same image text as Copy"
                        )
                    )
                }

                if let open {
                    Button {
                        openURL(open)
                    } label: {
                        Label("Open", systemImage: "safari")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Open"))
                    .accessibilityHint(
                        String(localized: "Opens the image URL from the feed in the system browser")
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}
