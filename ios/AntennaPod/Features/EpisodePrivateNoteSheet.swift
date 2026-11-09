import SwiftUI

/// Compact sheet to edit the local-only private note for one episode.
/// Mirrors per-feed Private note UX (TextEditor + Clear + character count); not RSS / gpodder / OPML / HTML / chapters / Share.
struct EpisodePrivateNoteSheet: View {
    @EnvironmentObject private var store: PodcastStore
    @Environment(\.dismiss) private var dismiss

    let episodeId: String

    @State private var draft = ""

    private var currentNote: String? {
        store.episodePrivateNote(for: episodeId)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $draft)
                        .frame(minHeight: 120)
                        .accessibilityLabel(String(localized: "Private note"))
                        .accessibilityHint(String(localized: "Optional local-only note for this episode. Not synced and not from the feed. Maximum 1000 characters."))
                        .accessibilityValue(
                            draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? String(localized: "Empty")
                                : draft
                        )
                        .onChange(of: draft) { _, newValue in
                            commitDraft(newValue)
                        }
                    if currentNote != nil || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button(String(localized: "Clear private note")) {
                            draft = ""
                            store.setEpisodePrivateNote(for: episodeId, nil)
                        }
                        .accessibilityLabel(String(localized: "Clear private note"))
                        .accessibilityHint(String(localized: "Removes the local private note for this episode immediately. No confirmation. Local only — not RSS / gpodder / OPML. Does not affect bookmarks, chapters, Share with position, playback, favorites, feed private notes, or the queue."))
                    }
                    Text(
                        String(
                            format: String(localized: "%lld / %lld characters"),
                            Int64(min(draft.count, EpisodePrivateNotes.maxLength)),
                            Int64(EpisodePrivateNotes.maxLength)
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel(
                        String(
                            format: String(localized: "%lld of %lld characters used"),
                            Int64(min(draft.count, EpisodePrivateNotes.maxLength)),
                            Int64(EpisodePrivateNotes.maxLength)
                        )
                    )
                } header: {
                    Text(String(localized: "Private note"))
                } footer: {
                    Text(String(localized: "Local only on this device — not from RSS, not synced to gpodder, and not written to OPML, HTML export, chapters, or Share. Distinct from bookmarks. Included in iOS JSON backup. Cleared when you unsubscribe from the podcast. Maximum 1000 characters."))
                }
            }
            .navigationTitle(String(localized: "Private note"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
            .onAppear {
                draft = currentNote ?? ""
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func commitDraft(_ newValue: String) {
        var next = newValue
        if next.count > EpisodePrivateNotes.maxLength {
            let end = next.index(next.startIndex, offsetBy: EpisodePrivateNotes.maxLength)
            next = String(next[..<end])
            if next != draft {
                draft = next
            }
        }
        let normalized = EpisodePrivateNotes.normalized(next)
        if currentNote != normalized {
            store.setEpisodePrivateNote(for: episodeId, normalized)
        }
    }
}
