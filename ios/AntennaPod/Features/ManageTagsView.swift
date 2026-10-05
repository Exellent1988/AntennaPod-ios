import SwiftUI
import UIKit

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
    @State private var showCopiedAlert = false
    @State private var copiedAlertMessage = ""
    @State private var copyFeedbackTick = 0

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    /// Full in-use tag vocabulary — rename/delete always target a specific name from this set.
    private var allTags: [String] {
        store.allTags
    }

    private var tagsPlainText: String {
        TagsExport.plainText(tags: allTags) { store.feeds(withTag: $0).count }
    }

    private var tagsShareText: String {
        TagsExport.shareText(tags: allTags) { store.feeds(withTag: $0).count }
    }

    private var canExportTags: Bool {
        !allTags.isEmpty
    }

    /// Visible tags; empty query shows the full list. Filters tag **names** only (client-side).
    private var filteredTags: [String] {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = allTags
        if q.isEmpty { return base }
        return base.filter { $0.localizedSearchContains(q) }
    }

    var body: some View {
        List {
            if allTags.isEmpty {
                ContentUnavailableView(
                    "No tags yet",
                    systemImage: "tag",
                    description: Text("Add tags on a podcast under Feed detail → gear → Tags / Folders. They also appear as filter chips on Subscriptions.")
                )
                .accessibilityLabel(String(localized: "No tags yet"))
                .accessibilityValue(noTagsEmptyStateAccessibilityValue)
                .accessibilityHint(String(localized: "Add a tag from Feed detail, then return here to rename or delete it."))
            } else if filteredTags.isEmpty {
                ContentUnavailableView(
                    "No matching tags",
                    systemImage: "magnifyingglass",
                    description: Text("No tags match your search.")
                )
                .accessibilityLabel(String(localized: "No matching tags"))
                .accessibilityValue(noMatchingTagsEmptyStateAccessibilityValue)
                .accessibilityHint(String(localized: "Clear or change Search tags to see existing tag names."))
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        copyTags()
                    } label: {
                        Label("Copy tags", systemImage: "doc.plaintext")
                    }
                    .disabled(!canExportTags)
                    .accessibilityLabel(String(localized: "Copy tags"))
                    .accessibilityHint(String(localized: "Copies the full tag vocabulary, not the search-filtered list, as plain text. Does not rename or delete tags. Does not export OPML folder structure."))

                    ShareLink(
                        item: tagsShareText,
                        subject: Text(String(localized: "Tags"))
                    ) {
                        Label("Share tags", systemImage: "square.and.arrow.up")
                    }
                    .disabled(!canExportTags)
                    .accessibilityLabel(String(localized: "Share tags"))
                    .accessibilityHint(String(localized: "Opens the system share sheet with the full tag vocabulary, not the search-filtered list, as plain text. Does not rename or delete tags. Does not export OPML folder structure."))
                } label: {
                    Label("Tags actions", systemImage: "ellipsis.circle")
                }
                .accessibilityLabel(String(localized: "Tags actions"))
                .accessibilityHint(String(localized: "Copy or share the full tag vocabulary as plain text. Does not rename or delete tags. Does not export OPML folder structure."))
                .disabled(!canExportTags)
            }
        }
        .searchable(text: $searchText, prompt: "Search tags")
        .onChange(of: searchText) { _, newValue in
            scheduleFilter(for: newValue)
        }
        .onDisappear {
            debounceTask?.cancel()
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

    private var noTagsEmptyStateAccessibilityValue: String {
        String(localized: "No tags are assigned to any podcast. Add a tag from Feed detail → gear → Tags / Folders.")
    }

    private var noMatchingTagsEmptyStateAccessibilityValue: String {
        String(localized: "The tag catalog is not empty, but no existing tag name matches the current search.")
    }

    private func copyTags() {
        let text = tagsPlainText
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        copiedAlertMessage = String(localized: "Tags copied to the pasteboard.")
        copyFeedbackTick += 1
        showCopiedAlert = true
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
