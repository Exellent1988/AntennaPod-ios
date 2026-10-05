import SwiftUI
import UIKit

struct AllEpisodesView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var downloads: DownloadService
    @State private var searchText = ""
    @State private var showEnqueueAllConfirm = false
    @State private var showEnqueueAllUnplayedConfirm = false
    @State private var showMarkAllPlayedConfirm = false
    @State private var showMarkAllUnplayedConfirm = false
    @State private var showArchiveAllConfirm = false
    @State private var showCopiedAlert = false
    @State private var copiedAlertMessage = ""
    @State private var copyFeedbackTick = 0

    /// Soft-capped catalog (`store.allEpisodes`, newest-500) — Add all to queue always uses this,
    /// **not** the chip/podcast/search filtered visible list (`items`).
    private var catalogItems: [InboxEpisode] {
        store.allEpisodes
    }

    /// Soft-capped All Episodes catalog episodes in **store** newest-first order
    /// (`PodcastStore.allEpisodes`, newest 500 by `pubDateEpochMs`).
    /// **Not** status/podcast/type/search / UI `allEpisodesSort` filtered.
    /// Same honesty as Add all / Play random / soft-cap.
    private var allEpisodesCatalogEpisodes: [PodcastEpisode] {
        catalogItems.map(\.episode)
    }

    /// Plain-text list of the **soft-capped** All Episodes catalog — not chip/type/sort/search filtered;
    /// never beyond newest-500.
    private var allEpisodesPlainText: String {
        AllEpisodesExport.plainText(episodes: allEpisodesCatalogEpisodes) { episode in
            store.displayTitle(containingEpisodeId: episode.id)
        }
    }

    /// Enabled when the soft-capped All Episodes catalog is non-empty (read-only export).
    private var canExportAllEpisodes: Bool {
        !catalogItems.isEmpty
    }

    /// “Episodes” header + body for system share sheet (same body as Copy). Matches nav title.
    private var allEpisodesShareText: String {
        AllEpisodesExport.shareText(episodes: allEpisodesCatalogEpisodes) { episode in
            store.displayTitle(containingEpisodeId: episode.id)
        }
    }

    /// Episodes from the **soft-capped All Episodes catalog** (`store.allEpisodes`, newest 500 by
    /// `pubDateEpochMs`) that are not already queued — same catalog as the list’s soft cap,
    /// **not** chip (`allEpisodesFilter`), podcast chip, or searchable filter.
    /// Confirm count and `enqueueAllEpisodes()` share this eligibility.
    /// **Soft-cap honesty:** never claims eligibility beyond the newest-500 set.
    private var enqueueAllEpisodesCandidatesCount: Int {
        catalogItems.filter { !store.isInQueue($0.episode.id) }.count
    }

    /// Unplayed, non-archived, not-already-queued episodes in the soft-capped All Episodes catalog.
    /// Deliberately ignores status/podcast/type/sort/search UI filters and never exceeds newest-500.
    private var enqueueAllUnplayedEpisodesCandidatesCount: Int {
        store.enqueueAllUnplayedEpisodesCandidates().count
    }

    /// Unplayed, non-archived episodes in the soft-capped All Episodes catalog — not status,
    /// podcast, type, sort, or search filtered. Same archive policy as feed Mark all as played.
    private var markAllEpisodesPlayedCandidatesCount: Int {
        catalogItems.filter {
            !store.isPlayed($0.episode.id) && !store.isArchived($0.episode.id)
        }.count
    }

    /// Played episodes in the soft-capped All Episodes catalog — not status, podcast, type, sort,
    /// or search filtered. Includes archived played episodes, matching feed Mark all as unplayed.
    private var markAllEpisodesUnplayedCandidatesCount: Int {
        catalogItems.filter { store.isPlayed($0.episode.id) }.count
    }

    /// Non-archived episodes in the soft-capped All Episodes catalog — not status, podcast, type,
    /// sort, or search filtered. Same catalog and eligibility as `archiveAllEpisodes()`.
    private var archiveAllEpisodesCandidatesCount: Int {
        catalogItems.filter { !store.isArchived($0.episode.id) }.count
    }

    /// Soft-capped All Episodes catalog episodes with playable media via shared
    /// `EpisodePlayRandom` (local file via `DownloadService.localURL` — downloads + local-folder
    /// `file://` — or streamable http(s) `downloadUrl`). Same newest-500 set as Add all
    /// (`store.allEpisodes`) — **not** status/podcast/type/search filtered. **Soft-cap honesty:**
    /// never invents eligibility beyond the capped catalog. Distinct from Add all / remaining-time
    /// visible counts.
    private var playRandomEligibleEpisodes: [PodcastEpisode] {
        EpisodePlayRandom.eligible(
            from: catalogItems.map(\.episode),
            localURL: { downloads.localURL(for: $0) }
        )
    }

    /// Prefer unplayed among `playRandomEligibleEpisodes` when any remain; otherwise all eligible
    /// (played allowed when every eligible capped episode is played, or none unplayed eligible).
    private var playRandomCandidates: [PodcastEpisode] {
        EpisodePlayRandom.candidates(
            from: playRandomEligibleEpisodes,
            preferUnplayed: true,
            isPlayed: { store.isPlayed($0) }
        )
    }

    /// Bound podcast chip from `AppSettings` (empty = All). Feed UUIDs only — never invent.
    private var podcastFilter: AllEpisodesPodcastFilter {
        AllEpisodesPodcastFilter.fromStorage(settings.allEpisodesPodcastFilter)
    }

    private var isPodcastFiltering: Bool {
        if case .feed = podcastFilter { return true }
        return false
    }

    /// Unique feeds that currently have at least one episode in the soft-capped All Episodes
    /// catalog (display-title A–Z). Built via `feed(containingEpisodeId:)` — never invent.
    private var allEpisodesPodcastFeeds: [PodcastFeed] {
        var seen = Set<UUID>()
        var feeds: [PodcastFeed] = []
        for item in catalogItems {
            guard let feed = store.feed(containingEpisodeId: item.episode.id) else { continue }
            if seen.insert(feed.id).inserted {
                feeds.append(feed)
            }
        }
        return allEpisodesPodcastsByDisplayTitle(feeds)
    }

    /// A–Z by the name the chip shows. Raw RSS title would place a renamed podcast
    /// where the old name sorts, so the visible label and the row disagree.
    private func allEpisodesPodcastsByDisplayTitle(_ feeds: [PodcastFeed]) -> [PodcastFeed] {
        feeds.sorted {
            store.displayTitle(for: $0).localizedCaseInsensitiveCompare(
                store.displayTitle(for: $1)
            ) == .orderedAscending
        }
    }

    private var podcastFilterChips: [AllEpisodesPodcastFilter] {
        var chips: [AllEpisodesPodcastFilter] = [.all]
        var feeds = allEpisodesPodcastFeeds
        // Keep a persisted selection visible (even if that feed no longer appears in the
        // soft-capped set) so the user can see why the list is empty and tap All.
        if case .feed(let id) = podcastFilter,
           !feeds.contains(where: { $0.id == id }),
           let feed = store.feeds.first(where: { $0.id == id }) {
            feeds.append(feed)
            feeds = allEpisodesPodcastsByDisplayTitle(feeds)
        }
        chips.append(contentsOf: feeds.map { .feed($0.id) })
        return chips
    }

    /// Drop a podcast chip whose feed is no longer subscribed. Otherwise the UUID
    /// stays selected with no chip, and every later All Episodes row in the
    /// newest-500 catalog looks filtered out. A still-subscribed feed with zero
    /// rows in that catalog keeps its chip.
    private func releaseAllEpisodesPodcastFilterIfFeedGone() {
        guard case .feed(let id) = AllEpisodesPodcastFilter.fromStorage(settings.allEpisodesPodcastFilter) else { return }
        guard !store.feeds.contains(where: { $0.id == id }) else { return }
        settings.allEpisodesPodcastFilter = ""
    }

    private func podcastChipTitle(_ chip: AllEpisodesPodcastFilter) -> String {
        switch chip {
        case .all:
            return String(localized: "All")
        case .feed(let id):
            if let shown = store.nonEmptyDisplayTitle(forFeedId: id) {
                return shown
            }
            if let feed = allEpisodesPodcastFeeds.first(where: { $0.id == id }),
               let shown = store.nonEmptyDisplayTitle(for: feed) {
                return shown
            }
            return String(localized: "Unknown podcast")
        }
    }

    /// Soft cap first (newest 500 via `store.allEpisodes`), then sort → status → podcast → type → search.
    /// **Honesty:** `store.allEpisodes` is already the newest-500 by `pubDateEpochMs`.
    /// Oldest / Shortest / Longest / Title A–Z / Title Z–A only reorder within that capped set — they do
    /// **not** pull older episodes from beyond the soft limit. Missing dates / unknown durations /
    /// empty titles sort last; stable tiebreaker is episode `id` (same as Inbox). Orphan episodes
    /// (missing feed) match **All** only.
    /// Search matches title / descriptionText / episode private note / any bookmark note via
    /// `PodcastStore.episodeMatchesLibraryQuery` (same fields as library / Feed detail / Queue /
    /// Favorites / History / Archived / Downloads / Home), plus feed title (`InboxEpisode.feedTitle`
    /// = display title). View-only — soft-cap / status / podcast / type chips / Play random / Add all
    /// stay soft-cap catalog scoped. **Not** chapters / transcripts.
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
            case .shortestFirst, .longestFirst:
                let shortestFirst = settings.allEpisodesSort == .shortestFirst
                switch (
                    knownDurationSecondsForAllEpisodesSort(lhs.episode),
                    knownDurationSecondsForAllEpisodesSort(rhs.episode)
                ) {
                case let (l?, r?):
                    if l != r {
                        return shortestFirst ? (l < r) : (l > r)
                    }
                    return lhs.episode.id < rhs.episode.id
                case (_?, nil):
                    return true // known before unknown
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.episode.id < rhs.episode.id
                }
            case .titleAscending, .titleDescending:
                return allEpisodesTitleSort(lhs.episode, rhs.episode, ascending: settings.allEpisodesSort == .titleAscending)
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
        switch podcastFilter {
        case .all:
            break
        case .feed(let feedId):
            base = base.filter { store.feed(containingEpisodeId: $0.episode.id)?.id == feedId }
        }
        if settings.allEpisodesEpisodeTypeFilter != .all {
            base = base.filter { settings.allEpisodesEpisodeTypeFilter.matches($0.episode) }
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return base }
        return base.filter { item in
            store.episodeMatchesLibraryQuery(item.episode, query: q)
                || item.feedTitle.localizedSearchContains(q)
        }
    }

    /// Type chips for the soft-capped All Episodes catalog (before status/podcast/type/search).
    private var episodeTypeFilterChips: [EpisodeTypeFilter] {
        EpisodeTypeFilter.chips(
            presentIn: catalogItems.map(\.episode),
            selected: settings.allEpisodesEpisodeTypeFilter
        )
    }

    private var showEpisodeTypeFilterChips: Bool {
        EpisodeTypeFilter.shouldShowChipRow(
            presentIn: catalogItems.map(\.episode),
            selected: settings.allEpisodesEpisodeTypeFilter
        )
    }

    /// Status, podcast, or episode-type chip only. Search is not a chip.
    private var hasAllEpisodesChipFilter: Bool {
        settings.allEpisodesFilter != .all
            || isPodcastFiltering
            || settings.allEpisodesEpisodeTypeFilter != .all
    }

    /// Visible no-match copy. A status, podcast, or episode-type chip keeps the filter
    /// sentence even when search is also set. Search-only uses the same trimmed
    /// `searchText` the list filters on (no debounce), so the sentence does not
    /// appear before the list is filtered.
    private var allEpisodesNoMatchDescription: String {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasAllEpisodesChipFilter || query.isEmpty {
            return String(localized: "No episodes match your filter.")
        }
        return String(localized: "No All Episodes match your search. Clear or change the search to see episodes.")
    }

    /// VoiceOver value distinguishes an empty soft-capped catalog from a view-only filter/search
    /// mismatch. Keep the visible ContentUnavailableView copy concise while naming active scopes.
    private var allEpisodesEmptyStateAccessibilityValue: String {
        guard !catalogItems.isEmpty else {
            return String(localized: "There are no episodes in All Episodes. Episodes from your subscriptions appear here, newest first.")
        }

        let queryIsActive = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var activeScopes: [String] = []
        if settings.allEpisodesFilter != .all {
            activeScopes.append(settings.allEpisodesFilter.label)
        }
        if isPodcastFiltering {
            activeScopes.append(podcastChipTitle(podcastFilter))
        }
        if settings.allEpisodesEpisodeTypeFilter != .all {
            activeScopes.append(settings.allEpisodesEpisodeTypeFilter.label)
        }
        let scope = activeScopes.joined(separator: ", ")

        if queryIsActive, !scope.isEmpty {
            return String(localized: "No All Episodes match your search and the active filters: \(scope). Clear the search or choose All or another filter.")
        }
        if queryIsActive {
            return String(localized: "No All Episodes match your search. Clear or change the search to see episodes.")
        }
        if !scope.isEmpty {
            return String(localized: "No All Episodes match the active filters: \(scope). Choose All or another filter.")
        }
        return String(localized: "No All Episodes match the current view. Choose All or another filter.")
    }

    /// AntennaPod-like info bar: episode count + remaining over the **visible** All Episodes list
    /// (soft cap newest-500 → sort → status → podcast → type → search). Remaining per episode =
    /// `max(0, duration − position)` when duration known; unplayed with duration contributes
    /// full duration; **played** (not current) → 0; **unknown duration skipped** (tilde when
    /// any skipped). Currently playing uses live `PlaybackService` position/duration.
    /// Wall-clock by default; optional Settings → Remaining time respects speed divides by feed/default speed (estimate).
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

    /// VoiceOver hint for the All Episodes remaining bar. The visible label stays the
    /// count and time. This says whether that time is wall-clock or divided by
    /// podcast/default speed, and that the bar is the newest-500 visible list.
    private var allEpisodesRemainingAccessibilityHint: String {
        if settings.remainingTimeRespectsSpeed {
            return String(localized: "Estimate. Remaining time respects speed is on, so each episode is divided by that podcast’s playback speed, or Default speed, never below 0.5. This is not the live session rate and not Volume boost. The All Episodes bar is the visible list after the newest-500 cap, then sort, status chip (All, Unplayed, Downloaded, or Favorites), podcast filter, episode type, and search. Sort changes order only and does not pull older episodes beyond that cap. Played episodes that are not currently playing count as zero. It is not the newest-500 catalog behind Add all to queue, Add all unplayed to queue, Mark all as played, Mark all as unplayed, Archive all, Play random, Copy all episodes, or Share all episodes. Unknown durations are left out and no time is invented. The episode that is playing uses the live position, but the divisor stays the podcast or default speed. This is not the Queue remaining bar, the Inbox remaining bar, the Subscriptions unplayed remaining bar, a Home preview remaining bar, the mini player, or Lock Screen. It does not play, download, or mark episodes played.")
        }
        return String(localized: "Wall-clock remaining. Remaining time respects speed is off, so playback speed does not change this total. The All Episodes bar is the visible list after the newest-500 cap, then sort, status chip (All, Unplayed, Downloaded, or Favorites), podcast filter, episode type, and search. Sort changes order only and does not pull older episodes beyond that cap. Played episodes that are not currently playing count as zero. It is not the newest-500 catalog behind Add all to queue, Add all unplayed to queue, Mark all as played, Mark all as unplayed, Archive all, Play random, Copy all episodes, or Share all episodes. Unknown durations are left out and no time is invented. The episode that is playing uses the live position. This is not the Queue remaining bar, the Inbox remaining bar, the Subscriptions unplayed remaining bar, a Home preview remaining bar, the mini player, or Lock Screen. It does not play, download, or mark episodes played.")
    }

    private var allEpisodesRemainingSummary: EpisodeRemainingTime.Summary {
        EpisodeRemainingTime.summarize(
            episodes: items.map(\.episode),
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

    /// Feed duration when known; else saved playback duration. Never invents a length.
    /// Same known-duration path as Queue / Feed detail duration sort (no live player).
    private func knownDurationSecondsForAllEpisodesSort(_ episode: PodcastEpisode) -> Double? {
        EpisodeRemainingTime.knownDurationSeconds(
            for: episode,
            savedDurationSeconds: store.playbackState(for: episode.id).durationSeconds
        )
    }

    /// Title A–Z / Z–A within soft-capped set: empty titles last; id tiebreak.
    private func allEpisodesTitleSort(_ lhs: PodcastEpisode, _ rhs: PodcastEpisode, ascending: Bool) -> Bool {
        let lt = lhs.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let rt = rhs.title.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (lt.isEmpty, rt.isEmpty) {
        case (false, true):
            return true
        case (true, false):
            return false
        case (true, true):
            return lhs.id < rhs.id
        case (false, false):
            let cmp = lt.localizedCaseInsensitiveCompare(rt)
            if cmp != .orderedSame {
                return ascending ? (cmp == .orderedAscending) : (cmp == .orderedDescending)
            }
            return lhs.id < rhs.id
        }
    }


    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(AllEpisodesFilter.allCases) { chip in
                            AllEpisodesFilterChip(
                                title: chip.label,
                                selected: settings.allEpisodesFilter == chip,
                                accessibilityHint: String(localized: "Filters the All Episodes list")
                            ) {
                                settings.allEpisodesFilter = chip
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }

            if !catalogItems.isEmpty, !allEpisodesPodcastFeeds.isEmpty || isPodcastFiltering {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(podcastFilterChips) { chip in
                                AllEpisodesFilterChip(
                                    title: podcastChipTitle(chip),
                                    selected: podcastFilter == chip,
                                    accessibilityHint: String(localized: "Filters the All Episodes list by podcast")
                                ) {
                                    settings.allEpisodesPodcastFilter = chip.storageValue
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                } header: {
                    Text("Podcasts")
                }
            }

            // itunes:episodeType chips — within soft-capped catalog; hide when no types present.
            if !catalogItems.isEmpty, showEpisodeTypeFilterChips {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(episodeTypeFilterChips) { chip in
                                AllEpisodesFilterChip(
                                    title: chip.label,
                                    selected: settings.allEpisodesEpisodeTypeFilter == chip,
                                    accessibilityHint: String(localized: "Filters the All Episodes list by episode type")
                                ) {
                                    settings.allEpisodesEpisodeTypeFilter = chip
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }

            // AntennaPod-like All Episodes info bar (visible soft-capped+filtered list remaining time).
            // Soft-cap honesty: sums only the newest-500 → sort → status → podcast → type → search set — never beyond.
            if let remainingLabel = allEpisodesRemainingInfoLabel {
                Section {
                    Text(remainingLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(allEpisodesRemainingAccessibilityLabel)
                        .accessibilityHint(allEpisodesRemainingAccessibilityHint)
                }
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
            }

            if catalogItems.isEmpty {
                ContentUnavailableView(
                    "No episodes yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Episodes from your subscriptions appear here, newest first.")
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(localized: "No episodes yet"))
                .accessibilityValue(allEpisodesEmptyStateAccessibilityValue)
            } else if items.isEmpty {
                ContentUnavailableView(
                    "No matching episodes",
                    systemImage: "magnifyingglass",
                    description: Text(allEpisodesNoMatchDescription)
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(localized: "No matching episodes"))
                .accessibilityValue(allEpisodesEmptyStateAccessibilityValue)
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
                            .accessibilityHint(
                                store.isPlayed(item.episode.id)
                                    ? String(localized: "Marks this episode as unplayed")
                                    : String(localized: "Marks this episode as played")
                            )
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
                .accessibilityValue(settings.allEpisodesSort.label)
                .accessibilityHint(String(localized: "Orders the All Episodes list within the newest-500 soft cap. Shortest and Longest use known duration; Title A–Z / Z–A by title; empty or unknown last. Does not pull older episodes beyond the cap."))
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        copyAllEpisodes()
                    } label: {
                        Label("Copy all episodes", systemImage: "doc.plaintext")
                    }
                    // Soft-capped All Episodes catalog (not status/podcast/type/UI sort/search).
                    .disabled(!canExportAllEpisodes)
                    .accessibilityLabel(String(localized: "Copy all episodes"))
                    .accessibilityHint(
                        String(localized: "Copies the newest-500 All Episodes catalog to the pasteboard")
                    )

                    ShareLink(
                        item: allEpisodesShareText,
                        subject: Text(String(localized: "Episodes"))
                    ) {
                        Label("Share all episodes", systemImage: "square.and.arrow.up")
                    }
                    // Same gates as Copy all episodes — soft-capped catalog.
                    .disabled(!canExportAllEpisodes)
                    .accessibilityLabel(String(localized: "Share all episodes"))
                    .accessibilityHint(
                        String(localized: "Opens the system share sheet with the newest-500 All Episodes catalog")
                    )

                    Button {
                        playRandomEpisode()
                    } label: {
                        Label("Play random", systemImage: "shuffle")
                    }
                    .disabled(playRandomCandidates.isEmpty)
                    .accessibilityLabel(String(localized: "Play random"))
                    .accessibilityHint(String(localized: "Plays a random episode from the newest-500 All Episodes catalog with playable media. Prefers unplayed when any remain. Ignores status, podcast, episode type, search, and sort filters. Does not pull older episodes beyond the soft cap. Does not reorder All Episodes. No confirmation."))

                    Button {
                        showEnqueueAllConfirm = true
                    } label: {
                        Label("Add all to queue", systemImage: "text.append")
                    }
                    .disabled(enqueueAllEpisodesCandidatesCount == 0)
                    .accessibilityHint(String(localized: "Asks for confirmation, then appends episodes from the soft-capped All Episodes catalog (newest 500 by publish date) that are not already queued, newest first within that cap, including played and archived. Ignores status, podcast, type, and search filters. Queue lock does not block enqueue."))

                    Button {
                        showEnqueueAllUnplayedConfirm = true
                    } label: {
                        Label("Add all unplayed to queue", systemImage: "text.badge.plus")
                    }
                    .disabled(enqueueAllUnplayedEpisodesCandidatesCount == 0)
                    .accessibilityLabel(String(localized: "Add all unplayed to queue"))
                    .accessibilityHint(
                        String(localized: "Appends unplayed, non-archived All Episodes not already queued (newest 500 soft cap); distinct from Add all to queue, which includes played and archived")
                    )

                    Button {
                        showMarkAllPlayedConfirm = true
                    } label: {
                        Label("Mark all as played", systemImage: "checkmark.circle")
                    }
                    .disabled(markAllEpisodesPlayedCandidatesCount == 0)
                    .accessibilityHint(
                        String(localized: "Asks for confirmation, then marks unplayed, non-archived episodes in the newest-500 All Episodes catalog as played. Ignores status, podcast, type, sort, and search filters; older episodes beyond the soft cap are not included. Auto-delete after playing still applies when enabled.")
                    )

                    Button {
                        showMarkAllUnplayedConfirm = true
                    } label: {
                        Label("Mark all as unplayed", systemImage: "circle")
                    }
                    .disabled(markAllEpisodesUnplayedCandidatesCount == 0)
                    .accessibilityHint(
                        String(localized: "Asks for confirmation, then marks played episodes in the newest-500 All Episodes catalog as unplayed, including archived episodes. Ignores status, podcast, type, sort, and search filters; older episodes beyond the soft cap are not included. Does not delete downloads, remove episodes from the queue, stop playback, or unarchive.")
                    )

                    Button {
                        showArchiveAllConfirm = true
                    } label: {
                        Label("Archive all", systemImage: "archivebox")
                    }
                    .disabled(archiveAllEpisodesCandidatesCount == 0)
                    .accessibilityHint(
                        String(localized: "Asks for confirmation, then archives non-archived episodes in the newest-500 All Episodes catalog. Ignores status, podcast, type, sort, and search filters; older episodes beyond the soft cap are not included. Archived does not mean played. Does not mark played, delete downloads, or clear the queue.")
                    )
                } label: {
                    Label("Episodes actions", systemImage: "ellipsis.circle")
                }
                // Menu stays available when soft-capped catalog non-empty so each action can disable per eligibility.
                .disabled(catalogItems.isEmpty)
                .accessibilityLabel(String(localized: "Episodes actions"))
                .accessibilityHint(
                    String(localized: "Copy all episodes, share all episodes, play random, add all to queue, add all unplayed to queue, mark all as played, mark all as unplayed, or archive all")
                )
            }
        }
        .searchable(text: $searchText, prompt: "Search all episodes")
        .onAppear {
            releaseAllEpisodesPodcastFilterIfFeedGone()
        }
        .onChange(of: store.feeds.map(\.id)) { _, _ in
            releaseAllEpisodesPodcastFilterIfFeedGone()
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
            Text("Appends \(enqueueAllEpisodesCandidatesCount) episodes to the end of the queue (newest first within the newest-500 soft cap). Already queued episodes are skipped. Uses the soft-capped All Episodes catalog (newest 500 by publish date), not the status, podcast, type, or search filter. Queue lock does not block enqueue.")
        }
        .confirmationDialog(
            "Add all unplayed to queue?",
            isPresented: $showEnqueueAllUnplayedConfirm,
            titleVisibility: .visible
        ) {
            Button("Add all unplayed to queue") {
                store.enqueueAllUnplayedEpisodes()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Appends \(enqueueAllUnplayedEpisodesCandidatesCount) unplayed, non-archived episodes to the end of the queue (newest first within the newest-500 soft cap). Already queued, played, and archived episodes are skipped. Uses the soft-capped All Episodes catalog (newest 500 by publish date), not the status, podcast, type, sort, or search filter; older episodes beyond the soft cap are not included. Queue lock does not block enqueue. Distinct from Add all to queue, which also includes played and archived episodes.")
        }
        .confirmationDialog(
            "Mark all as played?",
            isPresented: $showMarkAllPlayedConfirm,
            titleVisibility: .visible
        ) {
            Button("Mark all as played") {
                store.markAllEpisodesPlayed()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Marks \(markAllEpisodesPlayedCandidatesCount) unplayed, non-archived episodes as played. Uses the newest-500 All Episodes catalog by publish date, not the status, podcast, type, sort, or search filter; older episodes beyond the soft cap are not included. Auto-delete after playing still applies when enabled.")
        }
        .confirmationDialog(
            "Mark all as unplayed?",
            isPresented: $showMarkAllUnplayedConfirm,
            titleVisibility: .visible
        ) {
            Button("Mark all as unplayed") {
                store.markAllEpisodesUnplayed()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Marks \(markAllEpisodesUnplayedCandidatesCount) played episodes as unplayed, including archived episodes. Uses the newest-500 All Episodes catalog by publish date, not the status, podcast, type, sort, or search filter; older episodes beyond the soft cap are not included. Does not delete downloads, remove episodes from the queue, stop playback, or unarchive.")
        }
        .confirmationDialog(
            "Archive all?",
            isPresented: $showArchiveAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Archive all") {
                store.archiveAllEpisodes()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Archives \(archiveAllEpisodesCandidatesCount) non-archived episodes in the newest-500 All Episodes catalog by publish date, not the status, podcast, type, sort, or search filter; older episodes beyond the soft cap are not included. Archived does not mean played. Does not mark played, delete downloads, or clear the queue.")
        }
    }

    /// Pasteboard copy of the **soft-capped** All Episodes catalog (not status/podcast/type/UI sort/search).
    /// Newest-first store order within newest-500 — same catalog as Add all / Play random. Read-only.
    /// **Soft-cap honesty:** never exports beyond `PodcastStore.allEpisodes`.
    private func copyAllEpisodes() {
        let text = allEpisodesPlainText
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        copiedAlertMessage = String(localized: "Episodes copied to the pasteboard.")
        copyFeedbackTick += 1
        showCopiedAlert = true
    }

    /// Uniform pick via shared `EpisodePlayRandom.pick` among eligible (prefer unplayed);
    /// starts via `PlaybackService.play` (resume rules unchanged).
    /// No confirm; soft-capped newest-500 catalog only — does **not** invent episodes beyond the cap;
    /// no invented queue mutations beyond what `play` already does.
    private func playRandomEpisode() {
        guard let episode = EpisodePlayRandom.pick(
            from: playRandomEligibleEpisodes,
            preferUnplayed: true,
            isPlayed: { store.isPlayed($0) }
        ) else { return }
        _ = playback.play(episode: episode)
    }
}

private struct AllEpisodesFilterChip: View {
    let title: String
    let selected: Bool
    let accessibilityHint: String
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
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
