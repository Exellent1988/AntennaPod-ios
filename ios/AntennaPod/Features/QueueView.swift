import SwiftUI

struct QueueView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var downloads: DownloadService
    @Environment(\.editMode) private var editMode

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var showClearQueueConfirm = false

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    /// Non-empty debounced query — reorder is disabled while filtering (indices would not map to the full queue).
    private var isFiltering: Bool {
        !debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Visible queue rows; empty query shows the full queue order.
    private var filteredQueue: [PodcastEpisode] {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = store.queue
        if q.isEmpty { return base }
        return base.filter { episode in
            if episode.title.localizedCaseInsensitiveContains(q) { return true }
            let feedTitle = store.feed(containingEpisodeId: episode.id)?.title ?? ""
            return feedTitle.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if store.queue.isEmpty {
                    ContentUnavailableView(
                        "Queue empty",
                        systemImage: "list.bullet",
                        description: Text("Add episodes from a podcast feed. Edit mode lets you drag to reorder.")
                    )
                } else if isFiltering && filteredQueue.isEmpty {
                    ContentUnavailableView(
                        "No matching queue episodes",
                        systemImage: "magnifyingglass",
                        description: Text("No queue episodes match your search.")
                    )
                } else {
                    ForEach(filteredQueue) { episode in
                        EpisodeRow(
                            episode: episode,
                            feedTitle: store.feed(containingEpisodeId: episode.id)?.title ?? ""
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                store.removeFromQueue(episode)
                            } label: {
                                Label("Remove", systemImage: "minus.circle")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                store.archive(episode.id)
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                            .tint(.orange)
                        }
                    }
                    .onMove(perform: isFiltering ? nil : { source, destination in
                        store.moveQueue(from: source, to: destination)
                    })
                }
            }
            .navigationTitle("Queue")
            .searchable(text: $searchText, prompt: "Search queue")
            .onChange(of: searchText) { _, newValue in
                scheduleFilter(for: newValue)
            }
            .onChange(of: isFiltering) { _, filtering in
                // Drag reorder uses full-queue indices; leave Edit while a filter is active.
                if filtering {
                    editMode?.wrappedValue = .inactive
                }
            }
            .onDisappear {
                debounceTask?.cancel()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                        // Hide reorder while filtering — filtered IndexSet ≠ full queue.
                        .disabled(store.queue.isEmpty || isFiltering)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(role: .destructive) {
                            showClearQueueConfirm = true
                        } label: {
                            Label("Clear queue", systemImage: "trash")
                        }
                        // Clear always targets the full queue (not the filtered subset).
                        .disabled(store.queue.isEmpty)
                    } label: {
                        Label("Queue actions", systemImage: "ellipsis.circle")
                    }
                    .disabled(store.queue.isEmpty)
                }
            }
            .confirmationDialog(
                "Clear queue?",
                isPresented: $showClearQueueConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear queue", role: .destructive) {
                    store.clearQueue()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes \(store.queue.count) episodes from the queue. Does not stop playback, mark played, or delete downloads.")
            }
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
