import SwiftUI
import UIKit

/// Feed-provided `podcast:alternateEnclosure` / `podcast:source` list — **display-only**.
/// Shows type, bitrate, length, title/lang/height when available. http(s) source → Open URL; else Copy URI.
/// **Does not switch PlaybackService** to alternate streams. Cap + honesty footnote.
struct PodcastAlternateEnclosuresListView: View {
    @Environment(\.openURL) private var openURL

    let alternateEnclosures: [PodcastAlternateEnclosure]
    /// Section title (localized by caller).
    var title: String = String(localized: "Alternate media")

    @State private var showCopiedAlert = false
    @State private var copyFeedbackTick = 0

    private var capped: (shown: [PodcastAlternateEnclosure], truncated: Bool) {
        PodcastAlternateEnclosureDisplay.capped(alternateEnclosures)
    }

    var body: some View {
        let result = capped
        if !result.shown.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)

                ForEach(Array(result.shown.enumerated()), id: \.offset) { _, enclosure in
                    enclosureRow(enclosure)
                }

                Text(
                    String(
                        localized: "This app lists alternate media from the feed for information only. It does not switch playback to these streams."
                    )
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityLabel(
                    String(
                        localized: "This app lists alternate media from the feed for information only. It does not switch playback to these streams."
                    )
                )

                if result.truncated {
                    Text(String(localized: "Showing first 20 alternate media options from the feed."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(
                            String(localized: "Showing first 20 alternate media options from the feed.")
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .alert(String(localized: "Copied"), isPresented: $showCopiedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(String(localized: "Media URL copied to the pasteboard."))
            }
            .sensoryFeedback(.success, trigger: copyFeedbackTick)
        }
    }

    @ViewBuilder
    private func enclosureRow(_ enclosure: PodcastAlternateEnclosure) -> some View {
        let headline = enclosure.displayTitle ?? enclosure.displayType ?? enclosure.type
        let captionParts: [String] = {
            var parts: [String] = []
            if enclosure.displayTitle != nil, let mime = enclosure.displayType {
                parts.append(mime)
            }
            if let br = PodcastAlternateEnclosureDisplay.bitrateLabel(enclosure.bitrate) {
                parts.append(br)
            }
            if let len = PodcastAlternateEnclosureDisplay.lengthLabel(enclosure.length) {
                parts.append(len)
            }
            if let h = PodcastAlternateEnclosureDisplay.heightLabel(enclosure.height) {
                parts.append(h)
            }
            if let lang = PodcastAlternateEnclosureDisplay.languageLabel(enclosure.displayLang) {
                parts.append(lang)
            }
            if let rel = enclosure.displayRel {
                parts.append(rel)
            }
            if let codecs = enclosure.displayCodecs {
                parts.append(codecs)
            }
            return parts
        }()
        let a11y: String = {
            var parts: [String] = [String(localized: "Alternate media"), headline]
            if enclosure.markedDefault {
                parts.append(String(localized: "Default"))
            }
            parts.append(contentsOf: captionParts)
            return parts.joined(separator: ", ")
        }()

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "rectangle.stack.badge.play")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(headline)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if enclosure.markedDefault {
                    Text(String(localized: "Default"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(a11y)

            if !captionParts.isEmpty {
                Text(captionParts.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .accessibilityHidden(true)
            }

            ForEach(Array(enclosure.validSources.enumerated()), id: \.offset) { _, source in
                sourceRow(source)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func sourceRow(_ source: PodcastAlternateSource) -> some View {
        if let url = source.browserURL {
            Button {
                openURL(url)
            } label: {
                Label("Open URL", systemImage: "safari")
                    .font(.subheadline)
            }
            .accessibilityLabel(String(localized: "Open URL"))
            .accessibilityHint(
                String(localized: "Opens this alternate media URL from the feed in the system browser")
            )
        } else if let uri = source.displayURI {
            Text(uri)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
                .accessibilityLabel(String(localized: "Media URI \(uri)"))

            if let ct = source.displayContentType {
                Text(ct)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel(String(localized: "Content type \(ct)"))
            }

            Button {
                UIPasteboard.general.string = uri
                copyFeedbackTick += 1
                showCopiedAlert = true
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .font(.subheadline)
            }
            .accessibilityLabel(String(localized: "Copy"))
            .accessibilityHint(
                String(
                    localized: "Copies the alternate media URI to the pasteboard. Playback is not switched."
                )
            )
        }
    }
}
