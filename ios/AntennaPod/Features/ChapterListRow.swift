import SwiftUI

/// Shared chapter list row for Full player + `EpisodeChaptersSheet` (mini).
/// Optional http(s) chapter `img` thumbnail beside the title; hidden when missing / failed — never episode art.
/// Optional http(s) chapter `href`/`url` **Open link** as a secondary control — primary tap remains seek.
struct ChapterListRow: View {
    @Environment(\.openURL) private var openURL

    let startTimeText: String
    let title: String
    let imageURL: URL?
    /// Feed/JSON chapter link when http(s); nil hides Open link — never invent.
    let linkURL: URL?
    let trailingTimeLabel: String?
    let isCurrent: Bool
    /// Accessibility label without chapter-image mention (parent builds duration / remaining).
    let accessibilityBaseLabel: String
    let onSeek: () -> Void

    @State private var imageLoaded = false

    private var accessibilityLabelText: String {
        if imageURL != nil, imageLoaded {
            return accessibilityBaseLabel + ", " + String(localized: "Chapter image")
        }
        return accessibilityBaseLabel
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: onSeek) {
                HStack(alignment: .center, spacing: 12) {
                    Text(startTimeText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, alignment: .trailing)
                    ChapterImageThumbnail(url: imageURL, didLoad: $imageLoaded)
                    Text(title)
                        .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? .primary : .secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let trailingTimeLabel {
                        Text(trailingTimeLabel)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if isCurrent {
                        Image(systemName: "waveform")
                            .font(.caption)
                            .foregroundStyle(.tint)
                    }
                }
                .padding(.vertical, 8)
                .padding(.leading, 10)
                .padding(.trailing, linkURL == nil ? 10 : 4)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isCurrent ? Color.accentColor.opacity(0.12) : Color.clear)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabelText)
            .accessibilityHint(String(localized: "Seeks playback to this chapter"))
            .accessibilityAddTraits(isCurrent ? .isSelected : [])

            if let linkURL {
                Button {
                    openURL(linkURL)
                } label: {
                    Image(systemName: "safari")
                        .font(.body)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(String(localized: "Open link"))
                .accessibilityHint(String(localized: "Opens this chapter’s link in the system browser"))
                .padding(.trailing, 4)
            }
        }
    }
}
