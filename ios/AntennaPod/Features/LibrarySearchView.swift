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
        return EpisodeRemainingTime.episodesInfoBarLabel(for: librarySearchRemainingSummary)
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

    private var librarySearchRemainingSummary: EpisodeRemainingTime.Summary {
        EpisodeRemainingTime.summarize(
            episodes: episodes.map(\.episode),
            currentEpisodeId: playback.currentEpisode?.id,
            liveDurationSeconds: playback.durationSeconds,
            livePositionSeconds: playback.positionSeconds,
            isPlayed: { store.isPlayed($0) },
            savedDurationSeconds: { store.playbackState(for: $0).durationSeconds },
            savedPositionSeconds: { store.positionSeconds(for: $0) }
        )
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

