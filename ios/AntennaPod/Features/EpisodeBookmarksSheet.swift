import SwiftUI
import UIKit

/// List / add / delete user bookmarks for the current episode.
/// Tap a row → `PlaybackService.seek(toSeconds:)`. Swipe → remove.
/// Local-only (`bookmarks.json`); not gpodder; wall-clock positions; cap 50/episode.
/// Toolbar **Copy bookmarks** + **Share bookmarks** export a plain-text list matching
/// sheet order (newest-first): `m:ss`/`h:mm:ss` + note when non-empty; Share includes
/// the episode title header — same pasteboard / ShareLink honesty as chapters TOC / transcript.
struct EpisodeBookmarksSheet: View {
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var store: PodcastStore
    @Environment(\.dismiss) private var dismiss

    let episodeId: String

    @State private var noteDraft = ""
    @State private var showAtCapAlert = false
    @State private var showCopiedAlert = false
    @State private var copiedAlertMessage = ""
    @State private var copyFeedbackTick = 0

    private var bookmarks: [EpisodeBookmark] {
        store.bookmarks(for: episodeId)
    }

    private var episodeTitle: String? {
        if let title = store.episode(id: episodeId)?.title,
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        if playback.currentEpisode?.id == episodeId {
            let title = playback.currentEpisode?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return title.isEmpty ? nil : title
        }
        return nil
    }

    /// Plain list matching sheet order (newest-first) — local bookmarks only.
    private var bookmarksPlain: String {
        BookmarksExport.plainText(from: bookmarks)
    }

    private var canExportBookmarks: Bool {
        !bookmarksPlain.isEmpty
    }

    /// Episode title + bookmark list for system share sheet (same body as Copy).
    private var bookmarksShareText: String {
        BookmarksExport.shareText(from: bookmarks, episodeTitle: episodeTitle)
    }

    private var atCap: Bool {
        bookmarks.count >= EpisodeBookmarkStore.maxPerEpisode
    }

    private var canAdd: Bool {
        playback.currentEpisode?.id == episodeId
            && playback.positionSeconds.isFinite
            && playback.positionSeconds >= 0
            && !atCap
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if bookmarks.isEmpty {
                        Text(String(localized: "No bookmarks for this episode yet."))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(String(localized: "No bookmarks for this episode yet."))
                    } else {
                        ForEach(bookmarks) { bookmark in
                            Button {
                                seek(to: bookmark)
                            } label: {
                                bookmarkRow(bookmark)
                            }
                            .accessibilityLabel(bookmarkAccessibilityLabel(bookmark))
                            .accessibilityHint(String(localized: "Seeks playback to this bookmark"))
                        }
                        .onDelete(perform: deleteBookmarks)
                    }
                } header: {
                    Text(String(localized: "Bookmarks"))
                } footer: {
                    Text(listFooter)
                }

                Section {
                    TextField(String(localized: "Optional note"), text: $noteDraft)
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled(false)
                        .disabled(atCap)
                        .accessibilityLabel(String(localized: "Optional note"))
                        .accessibilityHint(String(localized: "Short note saved with the bookmark, up to 120 characters"))

                    Button {
                        addBookmark()
                    } label: {
                        Label(
                            String(localized: "Bookmark current position"),
                            systemImage: "bookmark.fill"
                        )
                    }
                    .disabled(!canAdd)
                    .accessibilityLabel(String(localized: "Bookmark current position"))
                    .accessibilityHint(addAccessibilityHint)
                    .accessibilityValue(format(playback.positionSeconds))
                } footer: {
                    Text(addFooter)
                }
            }
            .navigationTitle(String(localized: "Bookmarks"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        copyBookmarks()
                    } label: {
                        Image(systemName: "doc.plaintext")
                    }
                    .disabled(!canExportBookmarks)
                    .accessibilityLabel(String(localized: "Copy bookmarks"))
                    .accessibilityHint(String(localized: "Copies the bookmark list to the pasteboard"))

                    ShareLink(
                        item: bookmarksShareText,
                        subject: Text(episodeTitle ?? String(localized: "Bookmarks"))
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(!canExportBookmarks)
                    .accessibilityLabel(String(localized: "Share bookmarks"))
                    .accessibilityHint(
                        String(localized: "Opens the system share sheet with the episode title and bookmark list")
                    )
                }
            }
            .alert(
                String(localized: "Bookmark limit reached"),
                isPresented: $showAtCapAlert
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(String(localized: "This episode already has 50 bookmarks. Delete one to add another."))
            }
            .alert(
                String(localized: "Copied"),
                isPresented: $showCopiedAlert
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(copiedAlertMessage)
            }
            .sensoryFeedback(.success, trigger: copyFeedbackTick)
        }
        .presentationDetents([.medium, .large])
    }

    private var listFooter: String {
        let count = bookmarks.count
        if atCap {
            return String(
                localized: "\(count) of 50 bookmarks. Limit reached — delete one to add another. Local only; not synced via gpodder. Distinct from chapters and Share with position."
            )
        }
        return String(
            localized: "\(count) of 50 bookmarks. Local only; wall-clock positions; not synced via gpodder. Distinct from chapters and Share with position."
        )
    }

    private var addFooter: String {
        if atCap {
            return String(localized: "Limit of 50 bookmarks per episode reached.")
        }
        let pos = format(playback.positionSeconds)
        return String(localized: "Saves the current position (\(pos)) with an optional short note.")
    }

    private var addAccessibilityHint: String {
        if atCap {
            return String(localized: "Limit reached — delete a bookmark first")
        }
        return String(localized: "Saves the current playback position as a bookmark")
    }

    @ViewBuilder
    private func bookmarkRow(_ bookmark: EpisodeBookmark) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "bookmark.fill")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(format(bookmark.positionSeconds))
                    .font(.body.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)
                if !bookmark.note.isEmpty {
                    Text(bookmark.note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "forward.fill")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }

    private func bookmarkAccessibilityLabel(_ bookmark: EpisodeBookmark) -> String {
        let time = format(bookmark.positionSeconds)
        var parts = [String(localized: "Bookmark \(time)")]
        if !bookmark.note.isEmpty {
            parts.append(bookmark.note)
        }
        return parts.joined(separator: ", ")
    }

    private func seek(to bookmark: EpisodeBookmark) {
        guard playback.currentEpisode?.id == episodeId else { return }
        playback.seek(toSeconds: bookmark.positionSeconds)
        dismiss()
    }

    private func addBookmark() {
        guard playback.currentEpisode?.id == episodeId else { return }
        if atCap {
            showAtCapAlert = true
            return
        }
        let position = playback.positionSeconds
        guard position.isFinite, position >= 0 else { return }
        let note = EpisodeBookmarkStore.trimNote(noteDraft)
        let ok = store.addBookmark(
            episodeId: episodeId,
            positionSeconds: position,
            note: note
        )
        if ok {
            noteDraft = ""
        } else {
            showAtCapAlert = true
        }
    }

    private func deleteBookmarks(at offsets: IndexSet) {
        let items = bookmarks
        for index in offsets {
            guard items.indices.contains(index) else { continue }
            store.removeBookmark(episodeId: episodeId, bookmarkId: items[index].id)
        }
    }

    private func copyBookmarks() {
        let text = bookmarksPlain
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        copiedAlertMessage = String(localized: "Bookmarks copied to the pasteboard.")
        copyFeedbackTick += 1
        showCopiedAlert = true
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
