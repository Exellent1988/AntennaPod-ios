import SwiftUI

/// Global tag vocabulary manager: list tags with podcast counts, rename, and delete
/// (removes the label from feeds; does not unsubscribe). Uses `feed-tags.json` via `PodcastStore`.
/// Supports `.searchable` filter over already-known tag names (case-insensitive, ~250 ms debounce).
/// Rename/delete still apply to the **named tag across all feeds** (not a filtered subset of podcasts);
/// there is no bulk “delete all tags” action — per-row destructive ops stay on the visible rows only.
struct ManageTagsView: View {
    @EnvironmentObject private var store: PodcastStore

    @State private var renameFrom: String?
    @State private var renameDraft = ""
    @State private var showRenameAlert = false
    @State private var tagPendingDelete: String?

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    /// Full in-use tag vocabulary — rename/delete always target a specific name from this set.
    private var allTags: [String] {
        store.allTags
    }

    /// Visible tags; empty query shows the full list. Filters tag **names** only (client-side).
    private var filteredTags: [String] {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = allTags
        if q.isEmpty { return base }
        return base.filter { $0.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        List {
            if allTags.isEmpty {
                ContentUnavailableView(
                    "No tags yet",
                    systemImage: "tag",
                    description: Text("Add tags on a podcast under Feed detail → gear → Tags / Folders. They also appear as filter chips on Subscriptions.")
                )
            } else if filteredTags.isEmpty {
                ContentUnavailableView(
                    "No matching tags",
                    systemImage: "magnifyingglass",
                    description: Text("No tags match your search.")
                )
            } else {
                Section {
                    ForEach(filteredTags, id: \.self) { tag in
                        tagRow(tag)
                    }
                } footer: {
                    Text("Rename updates every podcast using that name. Delete removes the tag from those podcasts; subscriptions stay. Empty names disappear from this list.")
                }
            }
        }
        .navigationTitle("Manage tags")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search tags")
        .onChange(of: searchText) { _, newValue in
            scheduleFilter(for: newValue)
        }
        .onDisappear {
            debounceTask?.cancel()
        }
        .alert("Rename tag", isPresented: $showRenameAlert) {
            TextField("Tag name", text: $renameDraft)
                .accessibilityLabel(String(localized: "Tag name"))
            Button("Cancel", role: .cancel) {
                renameFrom = nil
            }
            Button("Rename") {
                if let from = renameFrom {
                    store.renameTag(from: from, to: renameDraft)
                }
                renameFrom = nil
            }
            .accessibilityHint(String(localized: "Applies the new name to every podcast that uses this tag"))
        } message: {
            Text("Renames this tag on every podcast that uses it. Clear the name to delete it everywhere.")
        }
        .confirmationDialog(
            "Delete tag?",
            isPresented: Binding(
                get: { tagPendingDelete != nil },
                set: { if !$0 { tagPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete tag", role: .destructive) {
                if let tag = tagPendingDelete {
                    store.deleteTag(tag)
                }
                tagPendingDelete = nil
            }
            .accessibilityHint(String(localized: "Removes the tag from all podcasts; does not unsubscribe"))
            Button("Cancel", role: .cancel) {
                tagPendingDelete = nil
            }
        } message: {
            if let tag = tagPendingDelete {
                let count = store.feeds(withTag: tag).count
                Text(String(format: String(localized: "Removes “%@” from %lld podcasts. Does not unsubscribe or delete downloads."), tag, count))
            }
        }
    }

    @ViewBuilder
    private func tagRow(_ tag: String) -> some View {
        let count = store.feeds(withTag: tag).count
        let countLabel = podcastCountLabel(count)
        HStack {
            Image(systemName: "tag")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(tag)
                    .font(.body)
                Text(countLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tag), \(countLabel)")
        .accessibilityHint(String(localized: "Swipe or use the context menu to rename or delete"))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                tagPendingDelete = tag
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .accessibilityLabel(String(localized: "Delete tag"))
            Button {
                beginRename(tag)
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.indigo)
            .accessibilityLabel(String(localized: "Rename tag"))
        }
        .contextMenu {
            Button {
                beginRename(tag)
            } label: {
                Label("Rename…", systemImage: "pencil")
            }
            Button(role: .destructive) {
                tagPendingDelete = tag
            } label: {
                Label("Delete tag", systemImage: "trash")
            }
        }
    }

    private func beginRename(_ tag: String) {
        renameFrom = tag
        renameDraft = tag
        showRenameAlert = true
    }

    private func podcastCountLabel(_ count: Int) -> String {
        if count == 1 {
            return String(localized: "1 podcast")
        }
        return String(format: String(localized: "%lld podcasts"), count)
    }

    private func scheduleFilter(for term: String) {
        debounceTask?.cancel()
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            debouncedQuery = ""
            return
        }
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: debounceNs)
            guard !Task.isCancelled else { return }
            debouncedQuery = trimmed
        }
    }
}
