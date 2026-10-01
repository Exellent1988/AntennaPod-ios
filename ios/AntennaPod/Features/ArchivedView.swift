import SwiftUI

struct ArchivedView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var settings: AppSettings

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var showRestoreAllConfirm = false

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    /// Full archived catalog (store order: newest archived first) — Restore all always uses this count.
    private var items: [ArchivedEpisode] {
        store.archivedEpisodes
    }

    /// Visible archived ordered by `AppSettings.archivedSort`.
    /// Sort key: `ArchivedEpisode.archivedAtEpochMs` (`archivedAtById` / `archived.json`).
    /// Empty query shows the full list; sort applies to search-filtered results too.
    /// Does not mutate `PodcastStore.archivedEpisodes` (Restore all counts stay on newest-first catalog).
    private var filteredItems: [ArchivedEpisode] {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = items
        let filtered: [ArchivedEpisode]
        if q.isEmpty {
            filtered = base
        } else {
            filtered = base.filter { item in
                if item.episode.title.localizedCaseInsensitiveContains(q) { return true }
                return item.feedTitle.localizedCaseInsensitiveContains(q)
            }
        }
        return filtered.sorted { lhs, rhs in
            switch settings.archivedSort {
            case .newestFirst:
                if lhs.archivedAtEpochMs != rhs.archivedAtEpochMs {
                    return lhs.archivedAtEpochMs > rhs.archivedAtEpochMs
                }
                return lhs.episode.id < rhs.episode.id
            case .oldestFirst:
                if lhs.archivedAtEpochMs != rhs.archivedAtEpochMs {
                    return lhs.archivedAtEpochMs < rhs.archivedAtEpochMs
                }
                return lhs.episode.id < rhs.episode.id
            }
        }
    }

    var body: some View {
        List {
            if items.isEmpty {
                ContentUnavailableView(
                    "No archived episodes",
                    systemImage: "archivebox",
                    description: Text("Archive hides episodes from Inbox without marking them played. Restore them here or from a feed.")
                )
            } else if filteredItems.isEmpty {
                ContentUnavailableView(
                    "No matching archived",
                    systemImage: "magnifyingglass",
                    description: Text("No archived episodes match your search.")
                )
            } else {
                ForEach(filteredItems) { item in
                    EpisodeRow(
                        episode: item.episode,
                        feedTitle: item.feedTitle,
                        dateOverride: Date(timeIntervalSince1970: Double(item.archivedAtEpochMs) / 1000),
                        dateAccessibilityLabel: String(localized: "Archived")
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            store.restore(item.episode.id)
                        } label: {
                            Label("Restore", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.green)
                    }
                }
            }
        }
        .navigationTitle("Archived")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search archived")
        .onChange(of: searchText) { _, newValue in
            scheduleFilter(for: newValue)
        }
        .onDisappear {
            debounceTask?.cancel()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker(selection: $settings.archivedSort) {
                        ForEach(ArchivedSort.allCases) { sort in
                            Label(sort.label, systemImage: sort.systemImage)
                                .tag(sort)
                        }
                    } label: {
                        Text("Sort")
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort archived")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showRestoreAllConfirm = true
                    } label: {
                        Label("Restore all", systemImage: "arrow.uturn.backward")
                    }
                    // Restore all always targets the full archived list (not the filtered subset).
                    .disabled(items.isEmpty)
                } label: {
                    Label("Archived actions", systemImage: "ellipsis.circle")
                }
                .disabled(items.isEmpty)
            }
        }
        .confirmationDialog(
            "Restore all?",
            isPresented: $showRestoreAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Restore all") {
                store.restoreAllArchived()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Restores \(items.count) archived episodes. Does not mark unplayed or delete downloads.")
        }
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
