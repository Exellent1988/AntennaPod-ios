import SwiftUI

/// Local library search results (subscriptions + episodes). Not iTunes / online discovery.
struct LibrarySearchResultsView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var playback: PlaybackService
    let query: String

    private var feeds: [PodcastFeed] {
        store.matchingFeeds(query: query)
    }

    private var episodes: [LibraryEpisodeHit] {
        store.matchingEpisodes(query: query)
    }

    private var isEmpty: Bool {
        feeds.isEmpty && episodes.isEmpty
    }

    /// AntennaPod-like info bar: episode count + remaining over **visible episode hits only**
    /// (`matchingEpisodes` for this query — the Episodes section rows). Podcast feed hits are
    /// **not** included (no invented feed remaining). Remaining per episode =
    /// `max(0, duration − position)` when duration known; unplayed with duration contributes
    /// full duration; **played** (not current) → 0; **unknown duration skipped** (tilde when
    /// any skipped). Currently playing uses live `PlaybackService` position/duration.
    /// Wall-clock only (no playback-speed divide). Distinct from Inbox remaining (hidden while
    /// this view replaces Inbox rows) and from full-library / tab-badge totals.
    private var librarySearchRemainingInfoLabel: String? {
        guard !episodes.isEmpty else { return nil }
        let summary = librarySearchRemainingSummary
        let episodesWord: String
        if summary.episodeCount == 1 {
            episodesWord = String(localized: "1 episode")
        } else {
            episodesWord = String(localized: "\(summary.episodeCount) episodes")
        }
        // All durations unknown — show count only (no invented time).
        guard summary.knownCount > 0 else {
            return episodesWord
        }
        let formatted = StatisticsView.formatDuration(summary.remainingSeconds)
        let timePart: String
        if summary.unknownCount > 0 {
            timePart = String(localized: "~\(formatted)")
        } else {
            timePart = formatted
        }
        return String(localized: "\(episodesWord) • \(timePart) left")
    }

    private var librarySearchRemainingAccessibilityLabel: String {
        guard let label = librarySearchRemainingInfoLabel else { return "" }
        var parts = [String(localized: "Library search remaining time \(label)")]
        let unknown = librarySearchRemainingSummary.unknownCount
        if unknown > 0 {
            parts.append(String(localized: "Remaining time excludes \(unknown) episode(s) with unknown duration"))
        }
        parts.append(
            String(localized: "Library search remaining time covers matching episode results only, not podcast hits or the full library")
        )
        return parts.joined(separator: ". ")
    }

    private var librarySearchRemainingSummary: LibrarySearchRemainingSummary {
        var remaining = 0.0
        var known = 0
        var unknown = 0
        for hit in episodes {
            let episode = hit.episode
            guard let duration = knownDurationSeconds(for: episode) else {
                unknown += 1
                continue
            }
            known += 1
            // Mark-played clears position; do not count full duration as still left
            // (unless this is the live current episode — use live position instead).
            if store.isPlayed(episode.id), playback.currentEpisode?.id != episode.id {
                continue
            }
            let position = positionSeconds(for: episode)
            remaining += max(0, duration - position)
        }
        return LibrarySearchRemainingSummary(
            episodeCount: episodes.count,
            remainingSeconds: remaining,
            knownCount: known,
            unknownCount: unknown
        )
    }

    /// Prefer live player duration when this episode is current; else feed `itunes:duration` /
    /// media; else saved playback duration. Never invents a length.
    private func knownDurationSeconds(for episode: PodcastEpisode) -> Double? {
        if playback.currentEpisode?.id == episode.id {
            let live = playback.durationSeconds
            if live.isFinite, live > 0 { return live }
        }
        if episode.hasKnownDuration {
            return episode.durationSeconds
        }
        let saved = store.playbackState(for: episode.id).durationSeconds
        if saved.isFinite, saved > 0 { return saved }
        return nil
    }

    /// Live player position when current; else saved progress (`0` when unplayed / cleared).
    private func positionSeconds(for episode: PodcastEpisode) -> Double {
        if playback.currentEpisode?.id == episode.id {
            let live = playback.positionSeconds
            return live.isFinite ? max(0, live) : 0
        }
        return max(0, store.positionSeconds(for: episode.id))
    }

    var body: some View {
        if isEmpty {
            ContentUnavailableView(
                "No results",
                systemImage: "magnifyingglass",
                description: Text("No subscriptions or episodes match “\(displayQuery)”.")
            )
        } else {
            // AntennaPod-like library search info bar (visible episode hits only remaining time).
            // Hidden when no episode matches — podcast feed hits alone do not invent remaining.
            if let remainingLabel = librarySearchRemainingInfoLabel {
                Section {
                    Text(remainingLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(librarySearchRemainingAccessibilityLabel)
                }
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
            }

            if !feeds.isEmpty {
                Section("Podcasts") {
                    ForEach(feeds) { feed in
                        NavigationLink(value: feed) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(feed.title)
                                    .font(.headline)
                                Text("\(feed.episodes.count) episodes")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if !episodes.isEmpty {
                Section("Episodes") {
                    ForEach(episodes) { hit in
                        EpisodeRow(episode: hit.episode, feedTitle: hit.feedTitle)
                    }
                }
            }
        }
    }

    private var displayQuery: String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? query : trimmed
    }
}

/// Sum of remaining seconds over visible Library search episode hits (not podcast feed rows).
private struct LibrarySearchRemainingSummary {
    var episodeCount: Int
    var remainingSeconds: Double
    var knownCount: Int
    var unknownCount: Int
}
