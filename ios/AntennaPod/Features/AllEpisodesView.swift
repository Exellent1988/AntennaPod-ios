import SwiftUI

struct AllEpisodesView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var downloads: DownloadService
    @State private var searchText = ""
    @State private var showEnqueueAllConfirm = false

    /// Soft-capped catalog (`store.allEpisodes`, newest-500) — Add all to queue always uses this,
    /// **not** the chip/search filtered visible list (`items`).
    private var catalogItems: [InboxEpisode] {
        store.allEpisodes
    }

    /// Episodes from the **soft-capped All Episodes catalog** (`store.allEpisodes`, newest 500 by
    /// `pubDateEpochMs`) that are not already queued — same catalog as the list’s soft cap,
    /// **not** chip (`allEpisodesFilter`) or searchable filter.
    /// Confirm count and `enqueueAllEpisodes()` share this eligibility.
    /// **Soft-cap honesty:** never claims eligibility beyond the newest-500 set.
    private var enqueueAllEpisodesCandidatesCount: Int {
        catalogItems.filter { !store.isInQueue($0.episode.id) }.count
    }

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

    /// AntennaPod-like info bar: episode count + remaining over the **visible** All Episodes list
    /// (soft cap newest-500 → sort → chip → search). Remaining per episode =
    /// `max(0, duration − position)` when duration known; unplayed with duration contributes
    /// full duration; **played** (not current) → 0; **unknown duration skipped** (tilde when
    /// any skipped). Currently playing uses live `PlaybackService` position/duration.
    /// Wall-clock only (no playback-speed divide).
    /// **Soft-cap honesty:** never claims remaining beyond the capped+filtered visible set.
    private var allEpisodesRemainingInfoLabel: String? {
        guard !items.isEmpty else { return nil }
        return EpisodeRemainingTime.episodesInfoBarLabel(for: allEpisodesRemainingSummary)
    }

    private var allEpisodesRemainingAccessibilityLabel: String {
        guard let label = allEpisodesRemainingInfoLabel else { return "" }
        var parts = [String(localized: "All Episodes remaining time \(label)")]
        let unknown = allEpisodesRemainingSummary.unknownCount
        if unknown > 0 {
            parts.append(String(localized: "Remaining time excludes \(unknown) episode(s) with unknown duration"))
        }
        return parts.joined(separator: ". ")
    }

    private var allEpisodesRemainingSummary: EpisodeRemainingTime.Summary {
        EpisodeRemainingTime.summarize(
            episodes: items.map(\.episode),
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

            // AntennaPod-like All Episodes info bar (visible soft-capped+filtered list remaining time).
            // Soft-cap honesty: sums only the newest-500 → sort → chip → search set — never beyond.
            if let remainingLabel = allEpisodesRemainingInfoLabel {
                Section {
                    Text(remainingLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(allEpisodesRemainingAccessibilityLabel)
                }
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
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
                .accessibilityLabel(String(localized: "Sort all episodes"))
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showEnqueueAllConfirm = true
                    } label: {
                        Label("Add all to queue", systemImage: "text.append")
                    }
                    .disabled(enqueueAllEpisodesCandidatesCount == 0)
                    .accessibilityHint(String(localized: "Appends All Episodes not already queued (newest 500 soft cap)"))
                } label: {
                    Label("Episodes actions", systemImage: "ellipsis.circle")
                }
                // Menu enabled whenever soft-capped catalog is non-empty (even if chip/search hides rows).
                .disabled(catalogItems.isEmpty)
            }
        }
        .searchable(text: $searchText, prompt: "Filter by title or podcast")
        .confirmationDialog(
            "Add all to queue?",
            isPresented: $showEnqueueAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Add all to queue") {
                store.enqueueAllEpisodes()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Appends \(enqueueAllEpisodesCandidatesCount) episodes to the end of the queue (newest first within the newest-500 soft cap). Already queued episodes are skipped. Uses the soft-capped All Episodes catalog (newest 500 by publish date), not the chip or search filter. Queue lock does not block enqueue.")
        }
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
