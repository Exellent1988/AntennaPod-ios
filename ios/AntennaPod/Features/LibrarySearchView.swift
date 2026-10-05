import SwiftUI

/// Local library search results (subscriptions + episodes). Not iTunes / online discovery.
struct LibrarySearchResultsView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var settings: AppSettings
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
    /// Wall-clock by default; optional Settings → Remaining time respects speed divides by feed/default speed (estimate). Distinct from Inbox remaining (hidden while
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

    /// VoiceOver hint for the Library search remaining bar. The visible label
    /// stays the count and time. This says whether that time is wall-clock or
    /// divided by podcast/default speed, and that the bar sums matching episode
    /// hits only — not podcast hits, the full library, the Inbox list, or other
    /// remaining bars. Search fields are episode title, description, episode
    /// private note, or bookmark note. Chapters and transcripts are not searched.
    private var librarySearchRemainingAccessibilityHint: String {
        if settings.remainingTimeRespectsSpeed {
            return String(localized: "Estimate. Remaining time respects speed is on, so each episode is divided by that podcast’s playback speed, or Default speed, never below 0.5. This is not the live session rate and not Volume boost. The Library search bar sums matching episode hits only: episodes across subscriptions whose title, description, episode private note, or bookmark note matches the query. Podcast hits are not included, and this is not the full library or the Inbox list. It does not search chapters or transcripts. Played episodes that are not currently playing count as zero. Unknown durations are left out and no time is invented. The episode that is playing uses the live position, but the divisor stays the podcast or default speed. This is not the Feed remaining bar, the Archived remaining bar, the Downloads remaining bar, the History remaining bar, the Favorites remaining bar, the All Episodes remaining bar, the Queue remaining bar, the Inbox remaining bar, the Subscriptions unplayed remaining bar, a Home preview remaining bar, the mini player, or Lock Screen. It does not play, download, or mark episodes played.")
        }
        return String(localized: "Wall-clock remaining. Remaining time respects speed is off, so playback speed does not change this total. The Library search bar sums matching episode hits only: episodes across subscriptions whose title, description, episode private note, or bookmark note matches the query. Podcast hits are not included, and this is not the full library or the Inbox list. It does not search chapters or transcripts. Played episodes that are not currently playing count as zero. Unknown durations are left out and no time is invented. The episode that is playing uses the live position. This is not the Feed remaining bar, the Archived remaining bar, the Downloads remaining bar, the History remaining bar, the Favorites remaining bar, the All Episodes remaining bar, the Queue remaining bar, the Inbox remaining bar, the Subscriptions unplayed remaining bar, a Home preview remaining bar, the mini player, or Lock Screen. It does not play, download, or mark episodes played.")
    }

    private var librarySearchRemainingSummary: EpisodeRemainingTime.Summary {
        EpisodeRemainingTime.summarize(
            episodes: episodes.map(\.episode),
            currentEpisodeId: playback.currentEpisode?.id,
            liveDurationSeconds: playback.durationSeconds,
            livePositionSeconds: playback.positionSeconds,
            isPlayed: { store.isPlayed($0) },
            savedDurationSeconds: { store.playbackState(for: $0).durationSeconds },
            savedPositionSeconds: { store.positionSeconds(for: $0) },
            effectivePlaybackSpeed: {
                let enabled = settings.remainingTimeRespectsSpeed
                _ = settings.defaultPlaybackSpeed
                return enabled ? { store.resolvedPlaybackSpeedForRemaining(for: $0) } : nil
            }()
        )
    }


    var body: some View {
        if isEmpty {
            ContentUnavailableView(
                "No results",
                systemImage: "magnifyingglass",
                description: Text("No subscriptions or episodes match “\(displayQuery)”.")
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "No library search results"))
            .accessibilityValue(
                String(localized: "No subscriptions or episodes match “\(displayQuery)”.")
            )
            .accessibilityHint(
                String(localized: "Change or clear the library search to see other subscriptions or episodes.")
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
                        .accessibilityHint(librarySearchRemainingAccessibilityHint)
                }
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
            }

            if !feeds.isEmpty {
                Section("Podcasts") {
                    ForEach(feeds) { feed in
                        NavigationLink(value: feed) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(store.displayTitle(for: feed))
                                    .font(.headline)
                                Text("\(feed.episodes.count) episodes")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(librarySearchPodcastAccessibilityLabel(for: feed))
                        .accessibilityValue(librarySearchPodcastAccessibilityValue(for: feed))
                        .accessibilityHint(String(localized: "Opens this podcast"))
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

    private func librarySearchPodcastAccessibilityLabel(for feed: PodcastFeed) -> String {
        let title = store.displayTitle(for: feed).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return String(localized: "Podcast title unavailable")
        }
        return String(localized: "Podcast \(title)")
    }

    private func librarySearchPodcastAccessibilityValue(for feed: PodcastFeed) -> String {
        String(localized: "\(feed.episodes.count) episodes")
    }

    private var displayQuery: String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? query : trimmed
    }
}

