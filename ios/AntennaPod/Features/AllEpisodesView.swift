import SwiftUI

struct AllEpisodesView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var downloads: DownloadService
    @State private var searchText = ""

    /// Soft cap first (newest 500 via `store.allEpisodes`), then sort → chip → search.
    /// **Honesty:** `store.allEpisodes` is already the newest-500 by `pubDateEpochMs`.
    /// Oldest first only reorders within that capped set — it does **not** pull older
    /// episodes from beyond the soft limit. Missing dates sort last; stable tiebreaker
    /// is episode `id` (same as Inbox).
    private var items: [InboxEpisode] {
        var base = store.allEpisodes.sorted { lhs, rhs in
            switch settings.allEpisodesSort {
            case .newestFirst:
                let l = lhs.episode.pubDateEpochMs ?? Int64.min
                let r = rhs.episode.pubDateEpochMs ?? Int64.min
                if l != r { return l > r }
                return lhs.episode.id < rhs.episode.id
            case .oldestFirst:
                let l = lhs.episode.pubDateEpochMs ?? Int64.max
                let r = rhs.episode.pubDateEpochMs ?? Int64.max
                if l != r { return l < r }
                return lhs.episode.id < rhs.episode.id
            }
        }
        switch settings.allEpisodesFilter {
        case .all:
            break
        case .unplayed:
            // Same spirit as Inbox: not played and not archived, but only within the capped set.
            base = base.filter { !store.isPlayed($0.episode.id) && !store.isArchived($0.episode.id) }
        case .downloaded:
            base = base.filter { downloads.isDownloaded($0.episode) }
        case .favorites:
            // Starred via PodcastStore.isFavorite / favorites.json — still within the capped set.
            base = base.filter { store.isFavorite($0.episode.id) }
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return base }
        return base.filter { item in
            item.episode.title.localizedCaseInsensitiveContains(q)
                || item.feedTitle.localizedCaseInsensitiveContains(q)
        }
    }

    private var isFiltering: Bool {
        settings.allEpisodesFilter != .all
            || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(AllEpisodesFilter.allCases) { chip in
                            AllEpisodesFilterChip(
                                title: chip.label,
                                selected: settings.allEpisodesFilter == chip
                            ) {
                                settings.allEpisodesFilter = chip
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }

            if items.isEmpty {
                if isFiltering {
                    ContentUnavailableView(
                        "No matching episodes",
                        systemImage: "magnifyingglass",
                        description: Text("No episodes match your filter.")
                    )
                } else {
                    ContentUnavailableView(
                        "No episodes yet",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Episodes from your subscriptions appear here, newest first.")
                    )
                }
            } else {
                ForEach(items) { item in
                    EpisodeRow(episode: item.episode, feedTitle: item.feedTitle)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                store.toggleArchived(item.episode.id)
                            } label: {
                                Label(
                                    store.isArchived(item.episode.id)
                                        ? String(localized: "Restore")
                                        : String(localized: "Archive"),
                                    systemImage: store.isArchived(item.episode.id)
                                        ? "arrow.uturn.backward" : "archivebox"
                                )
                            }
                            .tint(store.isArchived(item.episode.id) ? .green : .orange)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                store.togglePlayed(item.episode.id)
                            } label: {
                                Label(
                                    store.isPlayed(item.episode.id)
                                        ? String(localized: "Mark unplayed")
                                        : String(localized: "Mark played"),
                                    systemImage: store.isPlayed(item.episode.id) ? "circle" : "checkmark.circle"
                                )
                            }
                            .tint(.blue)
                        }
                }
            }
        }
        .navigationTitle("Episodes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker(selection: $settings.allEpisodesSort) {
                        ForEach(AllEpisodesSort.allCases) { sort in
                            Label(sort.label, systemImage: sort.systemImage)
                                .tag(sort)
                        }
                    } label: {
                        Text("Sort")
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort all episodes")
            }
        }
        .searchable(text: $searchText, prompt: "Filter by title or podcast")
    }
}

private struct AllEpisodesFilterChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(String(localized: "Filters the All Episodes list"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
