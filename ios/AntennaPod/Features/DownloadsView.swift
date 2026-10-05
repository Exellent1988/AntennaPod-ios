import SwiftUI
import UIKit

struct DownloadsView: View {
    @EnvironmentObject private var downloads: DownloadService
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var settings: AppSettings

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var showDeletePlayedConfirm = false
    @State private var showDeleteAllConfirm = false
    @State private var showCancelAllConfirm = false
    @State private var showEnqueueAllConfirm = false
    @State private var showEnqueueAllUnplayedConfirm = false
    @State private var showMarkAllPlayedConfirm = false
    @State private var showMarkAllUnplayedConfirm = false
    @State private var showArchiveAllConfirm = false
    @State private var showCopiedAlert = false
    @State private var copiedAlertMessage = ""
    @State private var copyFeedbackTick = 0
    /// Single download pending swipe-delete confirmation (nil = dialog dismissed).
    @State private var episodePendingDelete: PodcastEpisode?
    /// Episode pending swipe Remove-from-queue confirmation (nil = dismissed).
    @State private var episodePendingRemoveFromQueue: PodcastEpisode?

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    /// Visible downloaded episodes: played chip → podcast chip → search → sort.
    /// Played chip uses `PodcastStore.isPlayed`. Podcast chip uses feeds present in the
    /// current download set only (never invent). Sort by `AppSettings.downloadsSort`
    /// (date: prefer `downloadedAtEpochMs`, else `pubDateEpochMs`; size: `knownByteSize`;
    /// title: `localizedCaseInsensitiveCompare`, empty last; id tiebreak).
    /// Search matches title / descriptionText / episode private note / any bookmark note via
    /// `PodcastStore.episodeMatchesLibraryQuery` (same fields as library / Feed detail / Queue / Favorites / History / Archived), plus
    /// feed display title (`displayTitle(containingEpisodeId:)`). View-only —
    /// Does not mutate `DownloadService.downloads` (tab badge / Play random / Add all / Delete played / Delete all / Copy / Share stay full-catalog).
    /// Play random / Add all to queue / Mark all as played / Mark all as unplayed / Delete played / Delete all / Cancel all / Copy downloads / Share downloads stay full-catalog scoped.
    private var filteredDownloads: [DownloadedEpisode] {
        var base = downloads.downloads
        switch settings.downloadsFilter {
        case .all:
            break
        case .unplayed:
            base = base.filter { !store.isPlayed($0.episode.id) }
        case .played:
            base = base.filter { store.isPlayed($0.episode.id) }
        }
        switch podcastFilter {
        case .all:
            break
        case .feed(let feedId):
            base = base.filter { store.downloadFeed(for: $0)?.id == feedId }
        }
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered: [DownloadedEpisode]
        if q.isEmpty {
            filtered = base
        } else {
            filtered = base.filter { item in
                if store.episodeMatchesLibraryQuery(item.episode, query: q) { return true }
                let feedTitle = store.downloadDisplayTitle(for: item)
                return feedTitle.localizedSearchContains(q)
            }
        }
        return filtered.sorted { lhs, rhs in
            switch settings.downloadsSort {
            case .newestFirst:
                let l = lhs.downloadsSortEpochMs ?? Int64.min
                let r = rhs.downloadsSortEpochMs ?? Int64.min
                if l != r { return l > r }
                return lhs.episode.id < rhs.episode.id
            case .oldestFirst:
                let l = lhs.downloadsSortEpochMs ?? Int64.max
                let r = rhs.downloadsSortEpochMs ?? Int64.max
                if l != r { return l < r }
                return lhs.episode.id < rhs.episode.id
            case .largestFirst:
                // Unknown size last (same honesty as row caption — never invent bytes).
                let l = lhs.knownByteSize() ?? Int64.min
                let r = rhs.knownByteSize() ?? Int64.min
                if l != r { return l > r }
                return lhs.episode.id < rhs.episode.id
            case .smallestFirst:
                let l = lhs.knownByteSize() ?? Int64.max
                let r = rhs.knownByteSize() ?? Int64.max
                if l != r { return l < r }
                return lhs.episode.id < rhs.episode.id
            case .titleAscending, .titleDescending:
                return downloadsTitleSort(
                    lhs.episode,
                    rhs.episode,
                    ascending: settings.downloadsSort == .titleAscending
                )
            }
        }
    }

    /// Title A–Z / Z–A: empty titles last; id tiebreak.
    private func downloadsTitleSort(_ lhs: PodcastEpisode, _ rhs: PodcastEpisode, ascending: Bool) -> Bool {
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

    /// Bound podcast chip from `AppSettings` (empty = All). Feed UUIDs only — never invent.
    private var podcastFilter: DownloadsPodcastFilter {
        DownloadsPodcastFilter.fromStorage(settings.downloadsPodcastFilter)
    }

    private var isPodcastFiltering: Bool {
        if case .feed = podcastFilter { return true }
        return false
    }

    /// Unique feeds that currently have at least one completed download.
    /// Built from the visible download catalog via `feed(containingEpisodeId:)` — never invent.
    /// Order matches the chip label: display title (custom title when set, else RSS title).
    private var downloadPodcastFeeds: [PodcastFeed] {
        var seen = Set<UUID>()
        var feeds: [PodcastFeed] = []
        for item in downloads.downloads {
            guard let feed = store.downloadFeed(for: item) else { continue }
            if seen.insert(feed.id).inserted {
                feeds.append(feed)
            }
        }
        return downloadPodcastsByDisplayTitle(feeds)
    }

    /// A–Z by the name the chip shows. Raw RSS title would place a renamed podcast
    /// where the old name sorts, so the visible label and the row disagree.
    private func downloadPodcastsByDisplayTitle(_ feeds: [PodcastFeed]) -> [PodcastFeed] {
        feeds.sorted {
            store.displayTitle(for: $0).localizedCaseInsensitiveCompare(
                store.displayTitle(for: $1)
            ) == .orderedAscending
        }
    }

    private var podcastFilterChips: [DownloadsPodcastFilter] {
        var chips: [DownloadsPodcastFilter] = [.all]
        var feeds = downloadPodcastFeeds
        // Keep a persisted selection visible (even if that feed no longer has downloads)
        // so the user can see why the list is empty and tap All.
        if case .feed(let id) = podcastFilter,
           !feeds.contains(where: { $0.id == id }),
           let feed = store.feeds.first(where: { $0.id == id }) {
            feeds.append(feed)
            feeds = downloadPodcastsByDisplayTitle(feeds)
        }
        chips.append(contentsOf: feeds.map { .feed($0.id) })
        return chips
    }

    /// Drop a podcast chip whose feed is no longer subscribed. Otherwise the UUID
    /// stays selected with no chip, and every later Downloads row looks filtered out.
    /// A still-subscribed feed with zero Downloads episodes keeps its chip.
    private func releaseDownloadsPodcastFilterIfFeedGone() {
        guard case .feed(let id) = DownloadsPodcastFilter.fromStorage(settings.downloadsPodcastFilter) else { return }
        guard !store.feeds.contains(where: { $0.id == id }) else { return }
        settings.downloadsPodcastFilter = ""
    }

    private func podcastChipTitle(_ chip: DownloadsPodcastFilter) -> String {
        switch chip {
        case .all:
            return String(localized: "All")
        case .feed(let id):
            return store.nonEmptyDisplayTitle(forFeedId: id)
                ?? downloadPodcastFeeds.first(where: { $0.id == id }).flatMap { store.nonEmptyDisplayTitle(for: $0) }
                ?? String(localized: "Unknown podcast")
        }
    }

    /// Played-status or podcast chip only. Search is not a chip: the empty copy must
    /// not call a search miss a filter miss.
    private var hasDownloadsChipOrPodcastFilter: Bool {
        settings.downloadsFilter != .all || isPodcastFiltering
    }

    /// Visible empty copy when the catalog is non-empty but no row matches.
    /// Chip or podcast filter wins when one is set; otherwise this is a search miss.
    private var downloadsNoMatchMessage: String {
        if hasDownloadsChipOrPodcastFilter {
            return String(localized: "No downloads match your filter.")
        }
        return String(localized: "No downloads match your search.")
    }

    /// Played offline files eligible for bulk delete (skips favorites — matches auto-delete).
    /// **Global** across the full Downloads catalog — not scoped to the visible chip/search filter
    /// (same honesty as Clear history / Clear favorites / Restore all).
    private var playedDownloadsForDelete: [DownloadedEpisode] {
        downloads.playedDownloadsEligibleForDelete(store: store)
    }

    private var playedDownloadsDeleteSizeLabel: String {
        DownloadStorageUsage.formatBytes(downloads.playedDownloadsEligibleByteSize(store: store))
    }

    /// Full completed catalog size for Delete all confirmation (not chip/search filtered).
    private var deleteAllDownloadsSizeLabel: String {
        DownloadStorageUsage.formatBytes(downloads.completedDownloadsByteSize())
    }

    /// Episodes from the **full completed Downloads catalog** (`DownloadService.downloads`,
    /// catalog/persist order — oldest completed first) that are not already queued — same catalog
    /// as Delete played downloads / tab badge, **not** the chip/search filtered list.
    /// Confirm count and `enqueueAllDownloads()` share this eligibility.
    private var enqueueAllDownloadsCandidatesCount: Int {
        downloads.downloads.filter { !store.isInQueue($0.episode.id) }.count
    }

    /// Unplayed, non-archived, not-already-queued episodes in the full completed Downloads
    /// catalog. The count and enqueue action share this catalog-scoped eligibility; UI filters are ignored.
    private var enqueueAllUnplayedDownloadsCandidatesCount: Int {
        store.enqueueAllUnplayedDownloadsCandidates().count
    }

    /// Unplayed, non-archived episodes in the **full completed Downloads catalog** — not chip,
    /// podcast, search, or sort filtered. Same archive policy as All Episodes / feed Mark all as played.
    private var markAllDownloadsPlayedCandidatesCount: Int {
        store.markAllDownloadsPlayedCandidateCount()
    }

    /// Played episodes in the **full completed Downloads catalog** — not chip, podcast, search,
    /// or sort filtered. Includes archived played episodes, matching feed / All Episodes Mark all
    /// as unplayed.
    private var markAllDownloadsUnplayedCandidatesCount: Int {
        store.markAllDownloadsUnplayedCandidateCount()
    }

    /// Non-archived episodes in the **full completed Downloads catalog** — not chip, podcast,
    /// search, or sort filtered. Completed downloads only; archive is independent of played state.
    private var archiveAllDownloadsCandidatesCount: Int {
        downloads.downloads.filter { !store.isArchived($0.episode.id) }.count
    }

    /// Completed Downloads catalog rows with a local playable file on disk via shared
    /// `EpisodePlayRandom` (`.localFileOnly` — `DownloadService.localURL` under Documents/downloads).
    /// Full catalog — **not** played-chip / podcast-chip / searchable filtered.
    /// Distinct from Add all to queue / Delete played / Delete all / remaining-time visible counts.
    private var playRandomEligibleEpisodes: [PodcastEpisode] {
        EpisodePlayRandom.eligible(
            from: downloads.downloads.map(\.episode),
            localURL: { downloads.localURL(for: $0) },
            requirement: .localFileOnly
        )
    }

    /// Prefer unplayed among `playRandomEligibleEpisodes` when any remain; otherwise all eligible
    /// (played allowed when every eligible completed download is played, or none unplayed eligible).
    private var playRandomCandidates: [PodcastEpisode] {
        EpisodePlayRandom.candidates(
            from: playRandomEligibleEpisodes,
            preferUnplayed: true,
            isPlayed: { store.isPlayed($0) }
        )
    }

    /// Full completed Downloads catalog newest-completed-first (`downloadsSortEpochMs` desc, id
    /// tiebreak) — same spirit as Home `downloadsCatalogNewestFirst` / Delete all catalog.
    /// **Not** chip (`downloadsFilter` / podcast) / searchable / UI `downloadsSort`.
    /// Does **not** include in-flight or waiting rows.
    private var downloadsCatalogNewestFirst: [PodcastEpisode] {
        downloads.downloads.sorted { lhs, rhs in
            let l = lhs.downloadsSortEpochMs ?? Int64.min
            let r = rhs.downloadsSortEpochMs ?? Int64.min
            if l != r { return l > r }
            return lhs.episode.id < rhs.episode.id
        }.map(\.episode)
    }

    /// Plain-text list of the **full** completed Downloads catalog — not chip/search/UI sort filtered.
    /// Same honesty as Delete all / Add all / Play random / tab badge.
    private var downloadsPlainText: String {
        DownloadsExport.plainText(episodes: downloadsCatalogNewestFirst) { episode in
            store.displayTitle(containingEpisodeId: episode.id)
        }
    }

    /// Enabled when the full completed Downloads catalog is non-empty (read-only export).
    private var canExportDownloads: Bool {
        !downloads.downloads.isEmpty
    }

    /// “Downloads” header + body for system share sheet (same body as Copy).
    private var downloadsShareText: String {
        DownloadsExport.shareText(episodes: downloadsCatalogNewestFirst) { episode in
            store.displayTitle(containingEpisodeId: episode.id)
        }
    }

    /// AntennaPod-like info bar: episode count + remaining over the **visible** filtered list.
    /// Remaining per episode = `max(0, duration − position)` when duration known; unplayed with
    /// duration contributes full duration; **played** (not current) → 0; **unknown duration skipped**
    /// (tilde when any skipped). Currently playing uses live `PlaybackService` position/duration.
    /// Wall-clock by default; optional Settings → Remaining time respects speed divides by feed/default speed (estimate). Distinct from tab badge / Add all / Play random / Delete played / Delete all (full catalog).
    private var downloadsRemainingInfoLabel: String? {
        guard !filteredDownloads.isEmpty else { return nil }
        return EpisodeRemainingTime.episodesInfoBarLabel(for: downloadsRemainingSummary)
    }

    private var downloadsRemainingAccessibilityLabel: String {
        guard let label = downloadsRemainingInfoLabel else { return "" }
        var parts = [String(localized: "Downloads remaining time \(label)")]
        let unknown = downloadsRemainingSummary.unknownCount
        if unknown > 0 {
            parts.append(String(localized: "Remaining time excludes \(unknown) episode(s) with unknown duration"))
        }
        return parts.joined(separator: ". ")
    }


    /// VoiceOver hint for the Downloads remaining bar. The visible label stays the
    /// count and time. This says whether that time is wall-clock or divided by
    /// podcast/default speed, and that the bar is the played-chip+podcast+search+sort list.
    private var downloadsRemainingAccessibilityHint: String {
        if settings.remainingTimeRespectsSpeed {
            return String(localized: "Estimate. Remaining time respects speed is on, so each episode is divided by that podcast’s playback speed, or Default speed, never below 0.5. This is not the live session rate and not Volume boost. The Downloads bar is the visible list after the played-status chip, podcast filter, search, and sort. Sort changes order only. Played episodes that are not currently playing count as zero. It is not the full offline Downloads catalog behind the tab badge, Play random, Add all to queue, Add all unplayed to queue, Mark all as played, Mark all as unplayed, Archive all, Cancel all downloads, Delete played downloads, Delete all downloads, Copy downloads, or Share downloads, and not the Home Downloads preview. Unknown durations are left out and no time is invented. The episode that is playing uses the live position, but the divisor stays the podcast or default speed. This is not the History remaining bar, the Favorites remaining bar, the All Episodes remaining bar, the Queue remaining bar, the Inbox remaining bar, the Subscriptions unplayed remaining bar, a Home preview remaining bar, the mini player, or Lock Screen. It does not play, download, or mark episodes played.")
        }
        return String(localized: "Wall-clock remaining. Remaining time respects speed is off, so playback speed does not change this total. The Downloads bar is the visible list after the played-status chip, podcast filter, search, and sort. Sort changes order only. Played episodes that are not currently playing count as zero. It is not the full offline Downloads catalog behind the tab badge, Play random, Add all to queue, Add all unplayed to queue, Mark all as played, Mark all as unplayed, Archive all, Cancel all downloads, Delete played downloads, Delete all downloads, Copy downloads, or Share downloads, and not the Home Downloads preview. Unknown durations are left out and no time is invented. The episode that is playing uses the live position. This is not the History remaining bar, the Favorites remaining bar, the All Episodes remaining bar, the Queue remaining bar, the Inbox remaining bar, the Subscriptions unplayed remaining bar, a Home preview remaining bar, the mini player, or Lock Screen. It does not play, download, or mark episodes played.")
    }

    private var downloadsRemainingSummary: EpisodeRemainingTime.Summary {
        EpisodeRemainingTime.summarize(
            episodes: filteredDownloads.map(\.episode),
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
        NavigationStack {
            List {
                if let error = downloads.lastError {
                    Section {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Last download failed")
                                    .font(.subheadline.weight(.semibold))
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let latest = downloads.recentErrors.first {
                                    Text(latest.episodeTitle)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                    if !latest.feedTitle.isEmpty {
                                        Text(latest.feedTitle)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(DownloadsFilter.allCases) { chip in
                                DownloadsFilterChip(
                                    title: chip.label,
                                    selected: settings.downloadsFilter == chip,
                                    accessibilityHint: String(localized: "Filters the Downloads list")
                                ) {
                                    settings.downloadsFilter = chip
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }

                if !downloads.downloads.isEmpty, !downloadPodcastFeeds.isEmpty || isPodcastFiltering {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(podcastFilterChips) { chip in
                                    DownloadsFilterChip(
                                        title: podcastChipTitle(chip),
                                        selected: podcastFilter == chip,
                                        accessibilityHint: String(localized: "Filters the Downloads list by podcast")
                                    ) {
                                        settings.downloadsPodcastFilter = chip.storageValue
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

                // AntennaPod-like downloads info bar (visible filtered list remaining time).
                if let remainingLabel = downloadsRemainingInfoLabel {
                    Section {
                        Text(remainingLabel)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(downloadsRemainingAccessibilityLabel)
                            .accessibilityHint(downloadsRemainingAccessibilityHint)
                    }
                    .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                }

                if downloads.downloads.isEmpty {
                    ContentUnavailableView(
                        "No downloads",
                        systemImage: "arrow.down.circle",
                        description: Text("Downloaded episodes will appear here for offline playback.")
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized: "No downloads"))
                    .accessibilityValue(
                        String(localized: "Downloaded episodes will appear here for offline playback.")
                    )
                    .accessibilityHint(String(localized: "Download an episode to see it here."))
                } else if filteredDownloads.isEmpty {
                    ContentUnavailableView(
                        "No matching downloads",
                        systemImage: "magnifyingglass",
                        description: Text(downloadsNoMatchMessage)
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized: "No matching downloads"))
                    .accessibilityValue(downloadsNoMatchMessage)
                    .accessibilityHint(
                        String(localized: "Change or clear the Downloads filters or search to see other downloads.")
                    )
                } else {
                    Section {
                        ForEach(filteredDownloads) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.episode.title)
                                        .font(.headline)
                                    HStack(spacing: 6) {
                                        Text(downloadsRowSubtitle(for: item))
                                            .lineLimit(1)
                                        if let sizeLabel = item.formattedKnownByteSize {
                                            Text("·")
                                                .accessibilityHidden(true)
                                            Text(sizeLabel)
                                                .monospacedDigit()
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(downloadsRowAccessibilityLabel(for: item))
                                Spacer()
                                Button {
                                    playback.play(
                                        episode: item.episode,
                                        fileURL: downloads.localURL(for: item.episode)
                                    )
                                } label: {
                                    Image(systemName: "play.fill")
                                }
                                .buttonStyle(.bordered)
                                .accessibilityLabel(String(localized: "Play"))
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
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    store.playNext(
                                        item.episode,
                                        currentlyPlayingId: playback.currentEpisode?.id
                                    )
                                } label: {
                                    Label("Play Next", systemImage: "text.insert")
                                }
                                .tint(.teal)
                                if store.isInQueue(item.episode.id) {
                                    Button(role: .destructive) {
                                        episodePendingRemoveFromQueue = item.episode
                                    } label: {
                                        Label("Remove from queue", systemImage: "minus.circle")
                                    }
                                    .accessibilityHint(
                                        String(localized: "Asks for confirmation, then removes this episode from the queue")
                                    )
                                } else {
                                    Button {
                                        store.enqueue(item.episode)
                                    } label: {
                                        Label("Add to queue", systemImage: "text.append")
                                    }
                                    .tint(.purple)
                                }
                                Button(role: .destructive) {
                                    episodePendingDelete = item.episode
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Downloads")
            .searchable(text: $searchText, prompt: "Search downloads")
            .onChange(of: searchText) { _, newValue in
                scheduleFilter(for: newValue)
            }
            .onAppear {
                releaseDownloadsPodcastFilterIfFeedGone()
            }
            .onChange(of: store.feeds.map(\.id)) { _, _ in
                releaseDownloadsPodcastFilterIfFeedGone()
            }
            .onDisappear {
                debounceTask?.cancel()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker(selection: $settings.downloadsSort) {
                            ForEach(DownloadsSort.allCases) { sort in
                                Label(sort.label, systemImage: sort.systemImage)
                                    .tag(sort)
                            }
                        } label: {
                            Text("Sort")
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel(String(localized: "Sort downloads"))
                    .accessibilityHint(String(localized: "Orders the Downloads list. Largest and Smallest use known size; Title A–Z / Z–A by title; empty or unknown last. Does not change eviction order."))
                }
                ToolbarItem(placement: .status) {
                    if !downloads.downloads.isEmpty, downloads.storageUsage.fileCount > 0 {
                        Text(downloads.storageUsage.usedFormatted)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .accessibilityLabel(
                                String(localized: "Total downloads size \(downloads.storageUsage.usedFormatted)")
                            )
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        DownloadErrorsView()
                    } label: {
                        Label("Errors", systemImage: "exclamationmark.bubble")
                    }
                    .accessibilityLabel(String(localized: "Download errors"))
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            copyDownloads()
                        } label: {
                            Label("Copy downloads", systemImage: "doc.plaintext")
                        }
                        // Full completed Downloads catalog (not chip/search/UI sort).
                        .disabled(!canExportDownloads)
                        .accessibilityLabel(String(localized: "Copy downloads"))
                        .accessibilityHint(
                            String(localized: "Copies the full downloads list to the pasteboard")
                        )

                        ShareLink(
                            item: downloadsShareText,
                            subject: Text(String(localized: "Downloads"))
                        ) {
                            Label("Share downloads", systemImage: "square.and.arrow.up")
                        }
                        // Same gates as Copy downloads — full catalog.
                        .disabled(!canExportDownloads)
                        .accessibilityLabel(String(localized: "Share downloads"))
                        .accessibilityHint(
                            String(localized: "Opens the system share sheet with the full downloads list")
                        )

                        Button {
                            playRandomEpisode()
                        } label: {
                            Label("Play random", systemImage: "shuffle")
                        }
                        .disabled(playRandomCandidates.isEmpty)
                        .accessibilityLabel(String(localized: "Play random"))
                        .accessibilityHint(String(localized: "Plays a random completed download with a local file. Prefers unplayed when any remain."))

                        Button {
                            showEnqueueAllConfirm = true
                        } label: {
                            Label("Add all to queue", systemImage: "text.append")
                        }
                        .disabled(enqueueAllDownloadsCandidatesCount == 0)
                        .accessibilityHint(String(localized: "Appends downloaded episodes not already queued"))

                        Button {
                            showEnqueueAllUnplayedConfirm = true
                        } label: {
                            Label("Add all unplayed to queue", systemImage: "text.badge.plus")
                        }
                        .disabled(enqueueAllUnplayedDownloadsCandidatesCount == 0)
                        .accessibilityLabel(String(localized: "Add all unplayed to queue"))
                        .accessibilityHint(
                            String(localized: "Appends unplayed, non-archived downloaded episodes not already queued; ignores chip, podcast, search, and sort filters")
                        )

                        Button {
                            showMarkAllPlayedConfirm = true
                        } label: {
                            Label("Mark all as played", systemImage: "checkmark.circle")
                        }
                        .disabled(markAllDownloadsPlayedCandidatesCount == 0)
                        .accessibilityHint(
                            String(localized: "Marks unplayed, non-archived episodes in the full Downloads catalog as played; ignores chip, podcast, search, and sort filters")
                        )

                        Button {
                            showMarkAllUnplayedConfirm = true
                        } label: {
                            Label("Mark all as unplayed", systemImage: "circle")
                        }
                        .disabled(markAllDownloadsUnplayedCandidatesCount == 0)
                        .accessibilityHint(
                            String(localized: "Marks played episodes, including archived episodes, in the full Downloads catalog as unplayed; ignores chip, podcast, search, and sort filters and does not delete files")
                        )

                        Button {
                            showArchiveAllConfirm = true
                        } label: {
                            Label("Archive all", systemImage: "archivebox")
                        }
                        .disabled(archiveAllDownloadsCandidatesCount == 0)
                        .accessibilityHint(
                            String(localized: "Archives non-archived completed downloads in the full Downloads catalog; ignores chip, podcast, search, and sort filters; archived does not mean played")
                        )

                        Button {
                            showCancelAllConfirm = true
                        } label: {
                            Label("Cancel all downloads", systemImage: "xmark.circle")
                        }
                        .disabled(downloads.cancelAllInFlightCount == 0)
                        .accessibilityHint(String(localized: "Cancels in-progress and waiting downloads without deleting completed files"))

                        Button(role: .destructive) {
                            showDeletePlayedConfirm = true
                        } label: {
                            Label("Delete played downloads", systemImage: "trash")
                        }
                        .disabled(playedDownloadsForDelete.isEmpty)

                        Button(role: .destructive) {
                            showDeleteAllConfirm = true
                        } label: {
                            Label("Delete all downloads", systemImage: "trash.fill")
                        }
                        .disabled(downloads.downloads.isEmpty)
                        .accessibilityLabel(String(localized: "Delete all downloads"))
                        .accessibilityHint(
                            String(localized: "Deletes every completed offline file in the full Downloads catalog, including favorites; keeps played status, queue membership, favorites, and archive state")
                        )
                    } label: {
                        Label("Downloads actions", systemImage: "ellipsis.circle")
                    }
                    // Menu available when completed catalog is non-empty **or** anything is in-flight /
                    // waiting (Cancel all). Copy / Share / Play random / Add all / Cancel all / Delete
                    // played / Mark all as played / Mark all as unplayed / Delete all downloads each disable independently — same honesty as Favorites /
                    // History / Archived Copy / Share.
                    .disabled(downloads.downloads.isEmpty && downloads.cancelAllInFlightCount == 0)
                    .accessibilityLabel(String(localized: "Downloads actions"))
                    .accessibilityHint(
                        String(localized: "Copy downloads, share downloads, play random, add all to queue, add all unplayed to queue, mark all as played, mark all as unplayed, archive all, cancel all downloads, delete played downloads, or delete all downloads")
                    )
                }
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
                    store.enqueueAllDownloads()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Appends \(enqueueAllDownloadsCandidatesCount) downloaded episodes to the end of the queue (catalog order — oldest completed first). Already queued episodes are skipped. Uses the full Downloads catalog (same as Delete played downloads), not the chip/search filter. Queue lock does not block enqueue.")
            }
            .confirmationDialog(
                "Add all unplayed to queue?",
                isPresented: $showEnqueueAllUnplayedConfirm,
                titleVisibility: .visible
            ) {
                Button("Add all unplayed to queue") {
                    store.enqueueAllUnplayedDownloads()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Appends \(enqueueAllUnplayedDownloadsCandidatesCount) unplayed, non-archived downloaded episode(s) to the end of the queue (catalog order — oldest completed first). Already queued, played, and archived episodes are skipped. Uses the full completed Downloads catalog, not the chip, podcast, search, or sort filter. Queue lock does not block enqueue. Distinct from Add all to queue, which also includes played and archived downloads.")
            }
            .confirmationDialog(
                "Mark all as played?",
                isPresented: $showMarkAllPlayedConfirm,
                titleVisibility: .visible
            ) {
                Button("Mark all as played") {
                    store.markAllDownloadsPlayed()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Marks \(markAllDownloadsPlayedCandidatesCount) unplayed, non-archived downloaded episode(s) as played. Uses the full completed Downloads catalog — not the chip, podcast, search, or sort filter. Auto-delete after playing still applies when enabled; this does not itself clear downloads."
                )
            }
            .confirmationDialog(
                "Mark all as unplayed?",
                isPresented: $showMarkAllUnplayedConfirm,
                titleVisibility: .visible
            ) {
                Button("Mark all as unplayed") {
                    store.markAllDownloadsUnplayed()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Marks \(markAllDownloadsUnplayedCandidatesCount) played downloaded episode(s), including archived episodes, as unplayed. Uses the full completed Downloads catalog — not the chip, podcast, search, or sort filter. Does not delete download files, clear the queue, stop playback, or unarchive episodes."
                )
            }
            .confirmationDialog(
                "Archive all?",
                isPresented: $showArchiveAllConfirm,
                titleVisibility: .visible
            ) {
                Button("Archive all") {
                    store.archiveAllDownloads()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Archives \(archiveAllDownloadsCandidatesCount) non-archived downloaded episode(s) in the full completed Downloads catalog, not the chip, podcast, search, or sort filter. Archived does not mean played. Does not mark played, delete download files, clear the queue, or trigger auto-delete after playing."
                )
            }
            .confirmationDialog(
                "Cancel all downloads?",
                isPresented: $showCancelAllConfirm,
                titleVisibility: .visible
            ) {
                Button("Cancel all downloads") {
                    downloads.cancelAllInFlightDownloads()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Cancels \(downloads.cancelAllInFlightCount) in-progress or waiting download(s). Stops active transfers and clears the waiting queue. Does not delete completed offline files."
                )
            }
            .confirmationDialog(
                "Delete played downloads?",
                isPresented: $showDeletePlayedConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete played downloads", role: .destructive) {
                    downloads.deletePlayedDownloads(store: store)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Deletes \(playedDownloadsForDelete.count) played offline file(s) (\(playedDownloadsDeleteSizeLabel)). Keeps unplayed downloads and favorites. Does not mark unplayed, clear the queue, or delete all downloads."
                )
            }
            .confirmationDialog(
                "Delete all downloads?",
                isPresented: $showDeleteAllConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete all downloads", role: .destructive) {
                    downloads.deleteAllDownloads()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Deletes \(downloads.downloads.count) completed offline file(s) (\(deleteAllDownloadsSizeLabel)), including favorited downloads. Uses the full Downloads catalog — not the chip/search filter. Local files only — keeps played status, queue membership, favorites, archive state, and history. Distinct from Delete played downloads and from Clear queue."
                )
            }
            .confirmationDialog(
                "Delete download?",
                isPresented: Binding(
                    get: { episodePendingDelete != nil },
                    set: { if !$0 { episodePendingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: episodePendingDelete
            ) { episode in
                Button("Delete download", role: .destructive) {
                    downloads.delete(episode)
                    episodePendingDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    episodePendingDelete = nil
                }
            } message: { episode in
                Text(
                    "Delete download for \"\(episode.title)\"? Removes the local offline file only. Keeps played status, queue membership, favorites, and archive state."
                )
            }
            .confirmationDialog(
                "Remove from queue?",
                isPresented: Binding(
                    get: { episodePendingRemoveFromQueue != nil },
                    set: { if !$0 { episodePendingRemoveFromQueue = nil } }
                ),
                titleVisibility: .visible,
                presenting: episodePendingRemoveFromQueue
            ) { episode in
                Button("Remove from queue", role: .destructive) {
                    store.removeFromQueue(episode)
                    episodePendingRemoveFromQueue = nil
                }
                Button("Cancel", role: .cancel) {
                    episodePendingRemoveFromQueue = nil
                }
            } message: { episode in
                Text(
                    "Remove \"\(episode.title)\" from the queue? Removes from the queue only. Does not delete the download, mark played, or stop playback."
                )
            }
        }
    }

    /// Visible subtitle: the podcast display title when this episode is still on a
    /// subscription. The storage file name (percent-encoded id, or a SHA-256 name when
    /// the id is long) is not a podcast, so a sighted row was only a hash. Fall back
    /// to that file name when the feed is gone — never invent a podcast title.
    private func downloadsRowSubtitle(for item: DownloadedEpisode) -> String {
        let title = store.downloadDisplayTitle(for: item)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        return item.localFileURL.lastPathComponent
    }

    /// VoiceOver: title, podcast when known, size when known, and local file name.
    /// The feed title is deliberately omitted when the downloaded episode is stale or its
    /// feed metadata is missing; this keeps the spoken label honest instead of inventing a podcast.
    private func downloadsRowAccessibilityLabel(for item: DownloadedEpisode) -> String {
        var parts: [String] = []
        let episodeTitle = item.episode.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !episodeTitle.isEmpty {
            parts.append(episodeTitle)
        }

        let feedTitle = store.downloadDisplayTitle(for: item)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !feedTitle.isEmpty {
            parts.append(String(localized: "Podcast \(feedTitle)"))
        }

        if let sizeLabel = item.formattedKnownByteSize {
            parts.append(String(localized: "Size \(sizeLabel)"))
        }
        parts.append(item.localFileURL.lastPathComponent)
        return parts.joined(separator: ", ")
    }

    /// Pasteboard copy of the **full** completed Downloads catalog (not chip/search/UI sort). Read-only.
    /// Newest completed first — does **not** include in-flight/waiting rows.
    private func copyDownloads() {
        let text = downloadsPlainText
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        copiedAlertMessage = String(localized: "Downloads copied to the pasteboard.")
        copyFeedbackTick += 1
        showCopiedAlert = true
    }

    /// Uniform pick via shared `EpisodePlayRandom.pick` among eligible (prefer unplayed);
    /// starts via `PlaybackService.play` with local file path preferred (`fileURL` from
    /// `DownloadService.localURL`). Resume rules unchanged.
    /// No confirm; does not invent queue mutations beyond what `play` already does.
    private func playRandomEpisode() {
        guard let episode = EpisodePlayRandom.pick(
            from: playRandomEligibleEpisodes,
            preferUnplayed: true,
            isPlayed: { store.isPlayed($0) }
        ) else { return }
        let fileURL = downloads.localURL(for: episode)
        _ = playback.play(episode: episode, fileURL: fileURL)
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

private struct DownloadsFilterChip: View {
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

/// Persisted download failures (ring buffer) with clear action, searchable filter
/// over episode title / feed title / error message (already-saved log only), and
/// per-row **Retry** via existing `DownloadService.download(_:)` when resolvable.
struct DownloadErrorsView: View {
    @EnvironmentObject private var downloads: DownloadService
    @EnvironmentObject private var store: PodcastStore
    @State private var showClearConfirmation = false
    @State private var showCopiedAlert = false
    @State private var copiedAlertMessage = ""
    @State private var copyFeedbackTick = 0
    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    /// Full persisted ring buffer — Clear always targets this list (not the filtered subset).
    private var allErrors: [DownloadErrorEntry] {
        downloads.recentErrors
    }

    /// Plain-text body for the full persisted ring buffer — never the searchable subset.
    private var errorsPlainText: String {
        DownloadErrorsExport.plainText(from: allErrors)
    }

    /// Localized header + body for the system share sheet, still scoped to the full log.
    private var errorsShareText: String {
        DownloadErrorsExport.shareText(from: allErrors)
    }

    /// Visible errors; empty query shows the full log. Filters title, feed, and message.
    private var filteredErrors: [DownloadErrorEntry] {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = allErrors
        if q.isEmpty { return base }
        return base.filter { entry in
            if entry.episodeTitle.localizedSearchContains(q) { return true }
            if entry.feedTitle.localizedSearchContains(q) { return true }
            return entry.message.localizedSearchContains(q)
        }
    }

    var body: some View {
        List {
            if allErrors.isEmpty {
                ContentUnavailableView(
                    "No download errors",
                    systemImage: "checkmark.circle",
                    description: Text("Failed downloads will appear here (up to \(DownloadService.downloadErrorRingCapacity) recent).")
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "No download errors"))
                .accessibilityValue(
                    String(localized: "Failed downloads will appear here (up to \(DownloadService.downloadErrorRingCapacity) recent).")
                )
                .accessibilityHint(String(localized: "The log is empty. Failed downloads will appear here after a download error."))
            } else if filteredErrors.isEmpty {
                ContentUnavailableView(
                    "No matching errors",
                    systemImage: "magnifyingglass",
                    description: Text("No download errors match your search.")
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "No matching download errors"))
                .accessibilityValue(String(localized: "No download errors match your search."))
                .accessibilityHint(String(localized: "Change or clear the search to see other saved download errors."))
            } else {
                ForEach(filteredErrors) { entry in
                    DownloadErrorRow(entry: entry)
                }
            }
        }
        .navigationTitle("Download errors")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search download errors")
        .onChange(of: searchText) { _, newValue in
            scheduleFilter(for: newValue)
        }
        .onDisappear {
            debounceTask?.cancel()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear", role: .destructive) {
                    showClearConfirmation = true
                }
                // Clear always targets the full persisted log (not the filtered subset).
                .disabled(allErrors.isEmpty && downloads.lastError == nil)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        copyDownloadErrors()
                    } label: {
                        Label("Copy download errors", systemImage: "doc.plaintext")
                    }
                    .disabled(allErrors.isEmpty)
                    .accessibilityLabel(String(localized: "Copy download errors"))
                    .accessibilityHint(
                        String(localized: "Copies the full persisted download error log as plain text; ignores the search filter and is not OPML")
                    )

                    ShareLink(
                        item: errorsShareText,
                        subject: Text(String(localized: "Download errors"))
                    ) {
                        Label("Share download errors", systemImage: "square.and.arrow.up")
                    }
                    .disabled(allErrors.isEmpty)
                    .accessibilityLabel(String(localized: "Share download errors"))
                    .accessibilityHint(
                        String(localized: "Opens the system share sheet with the full persisted download error log as plain text; ignores the search filter and is not OPML")
                    )
                } label: {
                    Label("Download errors actions", systemImage: "ellipsis.circle")
                }
                .accessibilityLabel(String(localized: "Download errors actions"))
                .accessibilityHint(
                    String(localized: "Copy or share the full persisted download error log as plain text; actions ignore the search filter and are not OPML")
                )
                .disabled(allErrors.isEmpty)
            }
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
            "Clear download errors?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear errors", role: .destructive) {
                downloads.clearDownloadErrors()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes the saved error log and the Downloads banner. Offline files are kept.")
        }
    }

    /// Pasteboard copy of the full persisted ring buffer, not the searchable subset.
    private func copyDownloadErrors() {
        let text = errorsPlainText
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        copiedAlertMessage = String(localized: "Download errors copied to the pasteboard.")
        copyFeedbackTick += 1
        showCopiedAlert = true
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

/// One download-error log row with optional **Retry** (existing `DownloadService.download`).
private struct DownloadErrorRow: View {
    @EnvironmentObject private var downloads: DownloadService
    @EnvironmentObject private var store: PodcastStore
    let entry: DownloadErrorEntry

    private var canRetry: Bool {
        downloads.canRetryDownloadError(entry, store: store)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.episodeTitle.isEmpty ? String(localized: "Unknown episode") : entry.episodeTitle)
                    .font(.headline)
                if !entry.feedTitle.isEmpty {
                    Text(entry.feedTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(entry.message)
                    .font(.caption)
                    .foregroundStyle(.red)
                Text(entry.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Button("Retry") {
                Task {
                    await downloads.retryDownloadError(entry, store: store)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!canRetry)
            .accessibilityLabel(String(localized: "Retry"))
            .accessibilityHint(retryAccessibilityHint)
        }
        .padding(.vertical, 2)
    }

    /// VoiceOver hint — enabled vs disabled (missing / local-folder / in-flight).
    private var retryAccessibilityHint: String {
        if canRetry {
            return String(localized: "Enqueues this episode again via the normal download path")
        }
        if downloads.inProgress.contains(entry.episodeId) {
            return String(localized: "Download already in progress")
        }
        return String(localized: "Episode is no longer in the library or has no downloadable URL")
    }
}
