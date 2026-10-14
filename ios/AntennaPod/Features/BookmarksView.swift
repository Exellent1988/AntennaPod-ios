import SwiftUI
import UIKit

/// Catalog of every local episode bookmark across subscribed episodes.
/// Search only filters the visible rows; Copy / Share always export the full catalog.
struct BookmarksView: View {
    @EnvironmentObject private var store: PodcastStore

    @State private var searchText = ""
    @State private var showCopiedAlert = false
    @State private var copyFeedbackTick = 0
    @State private var selectedEpisodeId: String?

    /// Stable catalog order: newest bookmark first, then episode and bookmark id.
    /// Missing/stale episode metadata is retained in exports with honest fallback labels.
    private var catalogItems: [BookmarkExportItem] {
        store.bookmarksByEpisodeId.flatMap { episodeId, bookmarks in
            let episode = store.episode(id: episodeId)
            let episodeTitle = episode?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let feedTitle = store.displayTitle(containingEpisodeId: episodeId)
            return bookmarks.map { bookmark in
                BookmarkExportItem(
                    episodeTitle: episodeTitle,
                    feedTitle: feedTitle,
                    bookmark: bookmark,
                    episodeId: episodeId
                )
            }
        }.sorted { lhs, rhs in
            if lhs.bookmark.createdAtEpochMs != rhs.bookmark.createdAtEpochMs {
                return lhs.bookmark.createdAtEpochMs > rhs.bookmark.createdAtEpochMs
            }
            if lhs.episodeId != rhs.episodeId {
                return lhs.episodeId < rhs.episodeId
            }
            return lhs.bookmark.id.uuidString < rhs.bookmark.id.uuidString
        }
    }

    private var filteredItems: [BookmarkExportItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return catalogItems }
        return catalogItems.filter { item in
            item.episodeTitle.localizedSearchContains(query)
                || item.feedTitle.localizedSearchContains(query)
                || item.bookmark.note.localizedSearchContains(query)
                || BookmarksExport.positionText(item.bookmark.positionSeconds)
                    .localizedSearchContains(query)
        }
    }

    /// Copy / Share intentionally use `catalogItems`, not the search-filtered rows.
    private var bookmarksPlainText: String {
        BookmarksExport.plainText(items: catalogItems)
    }

    private var bookmarksShareText: String {
        BookmarksExport.shareText(items: catalogItems)
    }

    // List split from the modifier chain: together they exceed the CI type-checker time limit.
    private var bookmarksList: some View {
        List {
            if catalogItems.isEmpty {
                ContentUnavailableView(
                    emptyStateTitle,
                    systemImage: "bookmark",
                    description: Text(emptyStateDescription)
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(emptyStateTitle)
                .accessibilityValue(emptyStateDescription)
                .accessibilityHint(String(localized: "Bookmarks empty state"))
            } else if filteredItems.isEmpty {
                ContentUnavailableView(
                    emptyStateTitle,
                    systemImage: "magnifyingglass",
                    description: Text(emptyStateDescription)
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(emptyStateTitle)
                .accessibilityValue(emptyStateDescription)
                .accessibilityHint(String(localized: "Bookmarks search empty state"))
            } else {
                ForEach(filteredItems) { item in
                    Button {
                        selectedEpisodeId = item.episodeId
                    } label: {
                        bookmarkRow(item)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(bookmarkAccessibilityLabel(item))
                    .accessibilityHint(String(localized: "Opens this episode’s bookmarks"))
                }
            }
        }
    }

    var body: some View {
        bookmarksList
        .navigationTitle(String(localized: "Bookmarks"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: String(localized: "Search bookmarks"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        copyBookmarks()
                    } label: {
                        Label(String(localized: "Copy bookmarks"), systemImage: "doc.plaintext")
                    }
                    .disabled(catalogItems.isEmpty)
                    .accessibilityHint(String(localized: "Copies the full bookmarks catalog to the pasteboard; search is ignored"))

                    ShareLink(
                        item: bookmarksShareText,
                        subject: Text(String(localized: "Bookmarks"))
                    ) {
                        Label(String(localized: "Share bookmarks"), systemImage: "square.and.arrow.up")
                    }
                    .disabled(catalogItems.isEmpty)
                    .accessibilityHint(String(localized: "Opens the system share sheet with the full bookmarks catalog; search is ignored"))
                } label: {
                    Label(String(localized: "Bookmark actions"), systemImage: "ellipsis.circle")
                }
                .accessibilityLabel(String(localized: "Bookmark actions"))
                .accessibilityHint(String(localized: "Copy or share the full bookmarks catalog"))
            }
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showCopiedAlert
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(String(localized: "Bookmarks copied to the pasteboard."))
        }
        .sensoryFeedback(.success, trigger: copyFeedbackTick)
        .sheet(
            isPresented: Binding<Bool>(
                get: { selectedEpisodeId != nil },
                set: { (isPresented: Bool) in if !isPresented { selectedEpisodeId = nil } }
            )
        ) {
            if let selectedEpisodeId {
                EpisodeBookmarksSheet(episodeId: selectedEpisodeId)
            }
        }
    }

    @ViewBuilder
    private func bookmarkRow(_ item: BookmarkExportItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.displayEpisodeTitle)
                .font(.headline)
            Text(item.displayFeedTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(BookmarksExport.positionText(item.bookmark.positionSeconds))
                    .font(.body.monospacedDigit().weight(.semibold))
                if !item.bookmark.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(item.bookmark.note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 2)
    }

    private var emptyStateTitle: String {
        catalogItems.isEmpty
            ? String(localized: "No bookmarks")
            : String(localized: "No matching bookmarks")
    }

    private var emptyStateDescription: String {
        catalogItems.isEmpty
            ? String(localized: "Bookmarks saved from the player will appear here.")
            : String(localized: "No bookmarks match your search.")
    }

    private func bookmarkAccessibilityLabel(_ item: BookmarkExportItem) -> String {
        var parts = [
            item.displayEpisodeTitle,
            item.displayFeedTitle,
            BookmarksExport.positionText(item.bookmark.positionSeconds)
        ]
        let note = item.bookmark.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { parts.append(note) }
        return parts.joined(separator: ", ")
    }

    private func copyBookmarks() {
        guard !bookmarksPlainText.isEmpty else { return }
        UIPasteboard.general.string = bookmarksPlainText
        copyFeedbackTick += 1
        showCopiedAlert = true
    }
}
