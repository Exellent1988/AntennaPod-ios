import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: PodcastStore

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var showClearHistoryConfirm = false

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    /// Full history catalog (newest last-played first) — Clear history always uses this count.
    private var items: [HistoryEpisode] {
        store.historyEpisodes
    }

    /// Visible history; empty query shows the full list.
    private var filteredItems: [HistoryEpisode] {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = items
        if q.isEmpty { return base }
        return base.filter { item in
            if item.episode.title.localizedCaseInsensitiveContains(q) { return true }
            return item.feedTitle.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        List {
            if items.isEmpty {
                ContentUnavailableView(
                    "No history yet",
                    systemImage: "clock",
                    description: Text("Episodes you play or mark as played appear here, newest first.")
                )
            } else if filteredItems.isEmpty {
                ContentUnavailableView(
                    "No matching history",
                    systemImage: "magnifyingglass",
                    description: Text("No history matches your search.")
                )
            } else {
                ForEach(filteredItems) { item in
                    EpisodeRow(
                        episode: item.episode,
                        feedTitle: item.feedTitle,
                        dateOverride: Date(timeIntervalSince1970: Double(item.lastPlayedAtEpochMs) / 1000),
                        dateAccessibilityLabel: String(localized: "Last played")
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            store.removeFromHistory(item.episode.id)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if store.isPlayed(item.episode.id) {
                            Button {
                                store.markUnplayed(item.episode.id)
                            } label: {
                                Label("Mark unplayed", systemImage: "circle")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search history")
        .onChange(of: searchText) { _, newValue in
            scheduleFilter(for: newValue)
        }
        .onDisappear {
            debounceTask?.cancel()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(role: .destructive) {
                        showClearHistoryConfirm = true
                    } label: {
                        Label("Clear history", systemImage: "trash")
                    }
                    // Clear always targets the full history list (not the filtered subset).
                    .disabled(items.isEmpty)
                } label: {
                    Label("History actions", systemImage: "ellipsis.circle")
                }
                .disabled(items.isEmpty)
            }
        }
        .confirmationDialog(
            "Clear history?",
            isPresented: $showClearHistoryConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear history", role: .destructive) {
                store.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes \(items.count) episodes from history. Does not unsubscribe, delete downloads, or clear the queue.")
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
