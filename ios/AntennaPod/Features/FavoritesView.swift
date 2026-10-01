import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var settings: AppSettings

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var showClearFavoritesConfirm = false
    @State private var showEnqueueAllConfirm = false

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    /// Full favorites catalog (store order: newest favorited first) — Clear favorites always uses this count.
    private var items: [FavoriteEpisode] {
        store.favoriteEpisodes
    }

    /// Episodes from the **full Favorites catalog** (`store.favoriteEpisodes`, newest-favorited first) that are
    /// not already queued — same catalog as Clear favorites, **not** the searchable filtered list.
    /// Confirm count and `enqueueAllFavorites()` share this eligibility.
    private var enqueueAllFavoritesCandidatesCount: Int {
        items.filter { !store.isInQueue($0.episode.id) }.count
    }

    /// Visible favorites ordered by `AppSettings.favoritesSort`.
    /// Sort key: `FavoriteEpisode.favoritedAtEpochMs` (`favoriteAtById` / `favorites.json`).
    /// Empty query shows the full list; sort applies to search-filtered results too.
    /// Does not mutate `PodcastStore.favoriteEpisodes` (Home Favorites preview / Clear favorites stay newest-first catalog).
    private var filteredItems: [FavoriteEpisode] {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = items
        let filtered: [FavoriteEpisode]
        if q.isEmpty {
            filtered = base
        } else {
            filtered = base.filter { item in
                if item.episode.title.localizedCaseInsensitiveContains(q) { return true }
                return item.feedTitle.localizedCaseInsensitiveContains(q)
            }
        }
        return filtered.sorted { lhs, rhs in
            switch settings.favoritesSort {
            case .newestFirst:
                if lhs.favoritedAtEpochMs != rhs.favoritedAtEpochMs {
                    return lhs.favoritedAtEpochMs > rhs.favoritedAtEpochMs
                }
                return lhs.episode.id < rhs.episode.id
            case .oldestFirst:
                if lhs.favoritedAtEpochMs != rhs.favoritedAtEpochMs {
                    return lhs.favoritedAtEpochMs < rhs.favoritedAtEpochMs
                }
                return lhs.episode.id < rhs.episode.id
            }
        }
    }

    /// AntennaPod-like info bar: episode count + remaining over the **visible** Favorites list
    /// (sort + searchable filter). Remaining per episode = `max(0, duration − position)` when
    /// duration known; unplayed with duration contributes full duration; **played** (not current)
    /// → 0; **unknown duration skipped** (tilde when any skipped). Currently playing uses live
    /// `PlaybackService` position/duration. Wall-clock only (no playback-speed divide).
    /// Distinct from Clear favorites count (always full catalog).
    private var favoritesRemainingInfoLabel: String? {
        guard !filteredItems.isEmpty else { return nil }
        return EpisodeRemainingTime.episodesInfoBarLabel(for: favoritesRemainingSummary)
    }

    private var favoritesRemainingAccessibilityLabel: String {
        guard let label = favoritesRemainingInfoLabel else { return "" }
        var parts = [String(localized: "Favorites remaining time \(label)")]
        let unknown = favoritesRemainingSummary.unknownCount
        if unknown > 0 {
            parts.append(String(localized: "Remaining time excludes \(unknown) episode(s) with unknown duration"))
        }
        return parts.joined(separator: ". ")
    }

    private var favoritesRemainingSummary: EpisodeRemainingTime.Summary {
        EpisodeRemainingTime.summarize(
            episodes: filteredItems.map(\.episode),
            currentEpisodeId: playback.currentEpisode?.id,
            liveDurationSeconds: playback.durationSeconds,
            livePositionSeconds: playback.positionSeconds,
            isPlayed: { store.isPlayed($0) },
            savedDurationSeconds: { store.playbackState(for: $0).durationSeconds },
            savedPositionSeconds: { store.positionSeconds(for: $0) }
        )
    }


    var body: some View {
        List {
            // AntennaPod-like favorites info bar (visible sorted+filtered list remaining time).
            // Hidden when catalog empty or search matches nothing — not full-catalog Clear count.
            if let remainingLabel = favoritesRemainingInfoLabel {
                Section {
                    Text(remainingLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(favoritesRemainingAccessibilityLabel)
                }
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
            }

            if items.isEmpty {
                ContentUnavailableView(
                    "No favorites yet",
                    systemImage: "star",
                    description: Text("Star episodes from a feed or the full player. Favorites keep their downloads when auto-delete after playing is on.")
                )
            } else if filteredItems.isEmpty {
                ContentUnavailableView(
                    "No matching favorites",
                    systemImage: "magnifyingglass",
                    description: Text("No favorites match your search.")
                )
            } else {
                ForEach(filteredItems) { item in
                    EpisodeRow(
                        episode: item.episode,
                        feedTitle: item.feedTitle,
                        dateOverride: Date(timeIntervalSince1970: Double(item.favoritedAtEpochMs) / 1000),
                        dateAccessibilityLabel: String(localized: "Favorited")
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            store.toggleFavorite(item.episode.id)
                        } label: {
                            Label("Unfavorite", systemImage: "star.slash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            store.archive(item.episode.id)
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                        .tint(.orange)
                    }
                }
            }
        }
        .navigationTitle("Favorites")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search favorites")
        .onChange(of: searchText) { _, newValue in
            scheduleFilter(for: newValue)
        }
        .onDisappear {
            debounceTask?.cancel()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker(selection: $settings.favoritesSort) {
                        ForEach(FavoritesSort.allCases) { sort in
                            Label(sort.label, systemImage: sort.systemImage)
                                .tag(sort)
                        }
                    } label: {
                        Text("Sort")
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .accessibilityLabel(String(localized: "Sort favorites"))
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showEnqueueAllConfirm = true
                    } label: {
                        Label("Add all to queue", systemImage: "text.append")
                    }
                    .disabled(enqueueAllFavoritesCandidatesCount == 0)
                    .accessibilityHint(String(localized: "Appends favorite episodes not already queued"))

                    Button(role: .destructive) {
                        showClearFavoritesConfirm = true
                    } label: {
                        Label("Clear favorites", systemImage: "trash")
                    }
                    // Clear always targets the full favorites list (not the filtered subset).
                    .disabled(items.isEmpty)
                } label: {
                    Label("Favorites actions", systemImage: "ellipsis.circle")
                }
                .disabled(items.isEmpty)
            }
        }
        .confirmationDialog(
            "Add all to queue?",
            isPresented: $showEnqueueAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Add all to queue") {
                store.enqueueAllFavorites()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Appends \(enqueueAllFavoritesCandidatesCount) favorite episodes to the end of the queue (newest favorited first). Already queued episodes are skipped. Uses the full Favorites catalog (same as Clear favorites), not the searchable filter. Queue lock does not block enqueue.")
        }
        .confirmationDialog(
            "Clear favorites?",
            isPresented: $showClearFavoritesConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear favorites", role: .destructive) {
                store.clearFavorites()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes \(items.count) episodes from favorites. Does not delete downloads, archive, mark played, or clear the queue.")
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


