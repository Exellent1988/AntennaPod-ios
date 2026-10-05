import SwiftUI
import UIKit

/// Shared chapter list row for Full player + `EpisodeChaptersSheet` (mini).
/// Optional http(s) chapter `img` thumbnail beside the title; hidden when missing / failed — never episode art.
/// Displayed chapter start has distinct **Copy / Share** controls; optional http(s) chapter
/// `href`/`url` has **Copy / Share / Open link** controls — primary tap remains seek.
struct ChapterListRow: View {
    @Environment(\.openURL) private var openURL

    let startTimeText: String
    let title: String
    let imageURL: URL?
    /// Feed/JSON chapter link when http(s); nil hides Copy / Share / Open — never invent.
    let linkURL: URL?
    let trailingTimeLabel: String?
    let isCurrent: Bool
    /// Accessibility label without chapter-image mention (parent builds duration / remaining).
    let accessibilityBaseLabel: String
    /// When true, primary tap uses `jumpToPosition` finish path (start ≥ known duration).
    let seekFinishesEpisode: Bool
    let onSeek: () -> Void

    @State private var imageLoaded = false
    @State private var showCopiedAlert = false
    @State private var copiedMessage = String(localized: "Chapter link copied to the pasteboard.")
    @State private var copyFeedbackTick = 0

    /// A chapter title is feed/media metadata; hide title actions when it is missing.
    private var hasCopyableTitle: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A chapter start is feed/media metadata; hide start actions when the displayed value is missing.
    private var hasCopyableStart: Bool {
        !startTimeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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
                .padding(.trailing, linkURL == nil && !hasCopyableTitle && !hasCopyableStart ? 10 : 4)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isCurrent ? Color.accentColor.opacity(0.12) : Color.clear)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabelText)
            .accessibilityHint(
                seekFinishesEpisode
                    ? String(localized: "Finishes the episode the same way as a forward skip. No confirmation.")
                    : String(localized: "Seeks playback to this chapter’s start immediately. No confirmation. Does not mark played, change the queue, or delete downloads.")
            )
            .accessibilityAddTraits(isCurrent ? .isSelected : [])

            if hasCopyableStart {
                Button {
                    UIPasteboard.general.string = startTimeText
                    copiedMessage = String(localized: "Chapter start copied to the pasteboard.")
                    copyFeedbackTick += 1
                    showCopiedAlert = true
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.body)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(String(localized: "Copy chapter start"))
                .accessibilityHint(
                    String(localized: "Copies the exact displayed chapter start time to the pasteboard")
                )

                ShareLink(item: startTimeText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(String(localized: "Share chapter start"))
                .accessibilityHint(
                    String(localized: "Shares the exact displayed chapter start time as plain text")
                )
            }

            if hasCopyableTitle {
                Button {
                    UIPasteboard.general.string = title
                    copiedMessage = String(localized: "Chapter title copied to the pasteboard.")
                    copyFeedbackTick += 1
                    showCopiedAlert = true
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.body)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(String(localized: "Copy chapter title"))
                .accessibilityHint(String(localized: "Copies the displayed chapter title to the pasteboard"))

                ShareLink(item: title) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(String(localized: "Share chapter title"))
                .accessibilityHint(String(localized: "Shares the displayed chapter title as plain text"))
            }

            if let linkURL {
                Button {
                    UIPasteboard.general.string = linkURL.absoluteString
                    copiedMessage = String(localized: "Chapter link copied to the pasteboard.")
                    copyFeedbackTick += 1
                    showCopiedAlert = true
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.body)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(String(localized: "Copy chapter link"))
                .accessibilityHint(String(localized: "Copies this chapter’s link to the pasteboard"))

                ShareLink(item: linkURL) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(String(localized: "Share chapter link"))
                .accessibilityHint(String(localized: "Shares this chapter’s link"))

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
        .alert(String(localized: "Copied"), isPresented: $showCopiedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(copiedMessage)
        }
        .sensoryFeedback(.success, trigger: copyFeedbackTick)
    }
}
