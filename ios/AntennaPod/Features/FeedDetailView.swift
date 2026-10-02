import SwiftUI
import UIKit

struct FeedDetailView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var downloads: DownloadService
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openURL) private var openURL
    let feed: PodcastFeed
    @State private var showPerFeedSettings = false
    @State private var showDownloadAllConfirm = false
    @State private var showMarkAllPlayedConfirm = false
    @State private var showMarkAllUnplayedConfirm = false
    @State private var showEnqueueAllConfirm = false
    @State private var showEnqueueAllUnplayedConfirm = false
    @State private var showDeleteDownloadsConfirm = false
    @State private var showUnsubscribeConfirm = false
    @State private var showFeedURLCopied = false
    @State private var showFundingURLCopied = false
    @State private var showPodcastWebsiteURLCopied = false
    @State private var showPodcastGuidCopied = false
    @State private var showDiscussURLCopied = false
    @State private var showFeedDescription = false
    @State private var isRescanningLocalFolder = false
    @Environment(\.dismiss) private var dismiss
    @State private var copyFeedURLFeedbackTick = 0
    @State private var copyFundingURLFeedbackTick = 0
    @State private var copyPodcastWebsiteURLFeedbackTick = 0
    @State private var copyPodcastGuidFeedbackTick = 0
    @State private var copyDiscussURLFeedbackTick = 0
    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    /// Live feed from the store when available (episodes refresh after pull/refresh).
    private var liveFeed: PodcastFeed {
        store.feeds.first(where: { $0.id == feed.id }) ?? feed
    }

    /// Local nickname when set, else RSS `liveFeed.title`.
    private var feedDisplayTitle: String {
        store.displayTitle(for: liveFeed)
    }

    /// Local-only private note when set (FeedSettings); hide indicator when nil/empty.
    private var feedPrivateNote: String? {
        store.feedSettings(for: liveFeed.id).privateNote
    }

    private var feedTags: [String] {
        store.tags(for: liveFeed.id)
    }

    /// Channel description as plain text (HTML stripped). Empty → hide info toolbar control.
    private var plainFeedDescription: String {
        guard let raw = liveFeed.descriptionText else { return "" }
        return HTMLTextStripping.plainText(from: raw)
    }

    private var hasReadableFeedDescription: Bool {
        !plainFeedDescription.isEmpty
    }

    /// Channel author when the feed provided it (hidden when missing — never invent).
    private var displayAuthor: String? {
        liveFeed.displayAuthor
    }

    /// Localized language name (or raw code) when the feed provided a language — hidden when missing.
    private var displayLanguage: String? {
        liveFeed.displayLanguage
    }


    /// Last successful network refresh when known — hidden when nil / local-folder (never invent).
    private var lastRefreshedAt: Date? {
        guard !LocalFolderFeed.isLocalFolderFeed(liveFeed) else { return nil }
        return liveFeed.lastRefreshedAt
    }

    /// Channel podcast:medium raw string when the feed provided it — hidden when missing (never invent/remap).
    private var displayMedium: String? {
        liveFeed.displayMedium
    }

    /// Channel itunes:type label when the feed provided it — hidden when missing (never invent; display-only).
    private var displayItunesType: String? {
        liveFeed.displayItunesType
    }

    /// itunes:category texts when the feed provided them — empty → hide (never invent taxonomy).
    private var displayCategories: [String] {
        liveFeed.displayCategories
    }

    /// Channel podcast:person when the feed provided them — empty → hide (never invent people).
    private var displayPeople: [PodcastPerson] {
        liveFeed.displayPeople
    }

    /// Channel podcast:location when the feed provided them — empty → hide (never invent / never geocode).
    private var displayLocations: [PodcastLocation] {
        liveFeed.displayLocations
    }

    /// Channel podcast:socialInteract when the feed provided openable http(s) — empty → hide (never invent).
    private var displaySocialInteracts: [PodcastSocialInteract] {
        liveFeed.displaySocialInteracts
    }

    /// Channel podcast:value recipients when the feed provided them — empty → hide (display-only; no payments).
    private var displayValues: [PodcastValue] {
        liveFeed.values
    }

    private var hasDisplayValueRecipients: Bool {
        !liveFeed.displayValueRecipients.isEmpty
    }

    /// Most recent channel podcast:trailer when the feed provided one — hide when missing (never invent).
    /// Distinct from item itunes:episodeType=trailer (EpisodeRow badge).
    private var displayTrailer: PodcastTrailer? {
        liveFeed.displayTrailer
    }

    /// Channel podcast:liveItem when the feed provided them — empty → hide (display-only; no live player).
    private var displayLiveItems: [PodcastLiveItem] {
        liveFeed.displayLiveItems
    }

    /// Channel podcast:txt when the feed provided them — empty → hide (display-only Copy / Open; no special clients).
    private var displayTexts: [PodcastTxt] {
        liveFeed.displayTexts
    }

    /// Channel podcast:license when the feed provided them — empty → hide (display-only; no DRM).
    private var displayLicenses: [PodcastLicense] {
        liveFeed.displayLicenses
    }

    /// Channel podcast:images / podcast:image when the feed provided variants — empty → hide (Open/Copy; prefer one for artwork).
    private var displayImages: [PodcastImageVariant] {
        liveFeed.displayImages
    }

    /// Channel podcast:podroll when the feed provided remoteItems — empty → hide (never invent recommendations).
    private var displayPodrollItems: [PodcastRemoteItem] {
        liveFeed.displayPodrollItems
    }

    /// Channel podcast:publisher when the feed provided remoteItems — empty → hide (never invent publishers).
    private var displayPublisherItems: [PodcastRemoteItem] {
        liveFeed.displayPublisherItems
    }

    /// Podcast Index `podcast:guid` when the feed provided it — hide when missing (never invent).
    private var displayPodcastGuid: String? {
        liveFeed.displayPodcastGuid
    }

    /// VoiceOver for podcast:locked=yes badge + honest footnote (+ optional owner from feed).
    private var feedLockedAccessibilityLabel: String {
        var parts = [
            String(localized: "Locked"),
            String(localized: "This feed claims to be locked for transfer. This app does not verify ownership.")
        ]
        if let owner = liveFeed.displayLockedOwner {
            parts.append(String(localized: "Locked owner \(owner)"))
        }
        return parts.joined(separator: ". ")
    }

    /// VoiceOver for podcast:block / itunes:block yes badge + honest directory display-only footnote.
    private var feedBlockedAccessibilityLabel: String {
        liveFeed.podcastBlockAccessibilityLabel
    }

    /// Channel podcast:updateFrequency when present — hide when absent (never invent; display-only).
    private var displayUpdateFrequency: PodcastUpdateFrequency? {
        liveFeed.displayUpdateFrequency
    }

    /// Resolved sort for this feed: `FeedSettings.episodeSort` or global `AppSettings.feedEpisodeSort`.
    private var resolvedEpisodeSort: FeedEpisodeSort {
        store.feedSettings(for: feed.id).resolvedEpisodeSort(global: settings.feedEpisodeSort)
    }

    /// Episodes for this feed ordered by resolved per-feed/`Use global` sort.
    /// Date modes: `pubDateEpochMs` (missing last). Duration modes: known duration via
    /// `EpisodeRemainingTime.knownDurationSeconds` (feed when known, else saved playback —
    /// same path as Queue; never invent; unknown last). Title modes: `localizedCaseInsensitiveCompare`
    /// (empty titles last). Title then id tiebreak (date/duration); id only for title modes.
    /// Does not mutate stored feed order. itunes:type is display-only — never auto-changes this sort.
    private var sortedEpisodes: [PodcastEpisode] {
        liveFeed.episodes.sorted { lhs, rhs in
            switch resolvedEpisodeSort {
            case .newestFirst:
                let l = lhs.pubDateEpochMs ?? Int64.min
                let r = rhs.pubDateEpochMs ?? Int64.min
                if l != r { return l > r }
                return feedEpisodeTitleTiebreak(lhs, rhs)
            case .oldestFirst:
                let l = lhs.pubDateEpochMs ?? Int64.max
                let r = rhs.pubDateEpochMs ?? Int64.max
                if l != r { return l < r }
                return feedEpisodeTitleTiebreak(lhs, rhs)
            case .shortestFirst, .longestFirst:
                let shortestFirst = resolvedEpisodeSort == .shortestFirst
                switch (knownDurationSecondsForFeedSort(lhs), knownDurationSecondsForFeedSort(rhs)) {
                case let (l?, r?):
                    if l != r {
                        return shortestFirst ? (l < r) : (l > r)
                    }
                    return feedEpisodeTitleTiebreak(lhs, rhs)
                case (_?, nil):
                    return true // known before unknown
                case (nil, _?):
                    return false
                case (nil, nil):
                    return feedEpisodeTitleTiebreak(lhs, rhs)
                }
            case .titleAscending, .titleDescending:
                return feedEpisodeTitleSort(lhs, rhs, ascending: resolvedEpisodeSort == .titleAscending)
            }
        }
    }

    /// Feed duration when known; else saved playback duration. Never invents a length.
    private func knownDurationSecondsForFeedSort(_ episode: PodcastEpisode) -> Double? {
        EpisodeRemainingTime.knownDurationSeconds(
            for: episode,
            savedDurationSeconds: store.playbackState(for: episode.id).durationSeconds
        )
    }

    private func feedEpisodeTitleTiebreak(_ lhs: PodcastEpisode, _ rhs: PodcastEpisode) -> Bool {
        let cmp = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if cmp != .orderedSame { return cmp == .orderedAscending }
        return lhs.id < rhs.id
    }

    /// Title A–Z / Z–A: `localizedCaseInsensitiveCompare` on trimmed title; empty last; id tiebreak.
    private func feedEpisodeTitleSort(_ lhs: PodcastEpisode, _ rhs: PodcastEpisode, ascending: Bool) -> Bool {
        let lt = lhs.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let rt = rhs.title.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (lt.isEmpty, rt.isEmpty) {
        case (false, true):
            return true // non-empty before empty
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

    /// Toolbar Sort writes an explicit per-feed override (`feed-settings.json`); does not change other feeds.
    private var feedEpisodeSortBinding: Binding<FeedEpisodeSort> {
        Binding(
            get: { resolvedEpisodeSort },
            set: { value in
                store.updateFeedSettings(for: feed.id) { $0.episodeSort = value }
            }
        )
    }

    /// Visible episodes: sort → status chip → itunes:episodeType chip → search.
    /// Status via `AppSettings.feedEpisodeFilter` (`isPlayed`; Unplayed also excludes archived,
    /// same spirit as All Episodes Unplayed). Type via `feedEpisodeTypeFilter` (parsed
    /// `itunes:episodeType` only — never invent; missing matches All only). Empty query shows
    /// the chip-filtered sorted list. Matches title, optional descriptionText, episode private
    /// note, or any bookmark note via `PodcastStore.episodeMatchesLibraryQuery` (same fields as
    /// library search; **not** chapters / transcripts).
    private var filteredEpisodes: [PodcastEpisode] {
        var base = sortedEpisodes
        switch settings.feedEpisodeFilter {
        case .all:
            break
        case .unplayed:
            // Same spirit as All Episodes Unplayed / Inbox: not played and not archived.
            base = base.filter { !store.isPlayed($0.id) && !store.isArchived($0.id) }
        case .played:
            base = base.filter { store.isPlayed($0.id) }
        }
        if settings.feedEpisodeTypeFilter != .all {
            base = base.filter { settings.feedEpisodeTypeFilter.matches($0) }
        }
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return base }
        return base.filter { store.episodeMatchesLibraryQuery($0, query: q) }
    }

    /// Type chips for this feed’s episode catalog (before status/type/search). Hide zero-match.
    private var feedEpisodeTypeFilterChips: [EpisodeTypeFilter] {
        EpisodeTypeFilter.chips(presentIn: feed.episodes, selected: settings.feedEpisodeTypeFilter)
    }

    private var showFeedEpisodeTypeFilterChips: Bool {
        EpisodeTypeFilter.shouldShowChipRow(presentIn: feed.episodes, selected: settings.feedEpisodeTypeFilter)
    }

    private var isFiltering: Bool {
        settings.feedEpisodeFilter != .all
            || settings.feedEpisodeTypeFilter != .all
            || !debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// AntennaPod-like info bar: episode count + remaining over the **visible** Feed detail list
    /// (sort → status → type → searchable). Remaining per episode = `max(0, duration − position)` when
    /// duration known; unplayed with duration contributes full duration; **played** (not current)
    /// → 0; **unknown duration skipped** (tilde when any skipped). Currently playing uses live
    /// `PlaybackService` position/duration. Wall-clock by default; optional Settings → Remaining time respects speed divides by feed/default speed (estimate).
    /// Distinct from **Download all unplayed** / **Mark all as played** / **Mark all as unplayed** / **Add all unplayed to queue** / **Add all to queue** / **Delete downloads** / **Play random** full-feed eligibility counts.
    private var feedRemainingInfoLabel: String? {
        guard !filteredEpisodes.isEmpty else { return nil }
        return EpisodeRemainingTime.episodesInfoBarLabel(for: feedRemainingSummary)
    }

    private var feedRemainingAccessibilityLabel: String {
        guard let label = feedRemainingInfoLabel else { return "" }
        var parts = [String(localized: "Feed remaining time \(label)")]
        let unknown = feedRemainingSummary.unknownCount
        if unknown > 0 {
            parts.append(String(localized: "Remaining time excludes \(unknown) episode(s) with unknown duration"))
        }
        return parts.joined(separator: ". ")
    }

    private var feedRemainingSummary: EpisodeRemainingTime.Summary {
        EpisodeRemainingTime.summarize(
            episodes: filteredEpisodes,
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


    /// Unplayed, not archived, not downloaded, http(s) enclosure — newest first, soft-capped
    /// by `AppSettings.feedDownloadUnplayedSoftCap` (default 50; always ≥1).
    /// Bulk **Download all unplayed** always uses full-feed eligibility (not the filtered subset).
    private var downloadAllCandidates: [PodcastEpisode] {
        downloads.eligibleForFeedDownloadAll(
            in: liveFeed,
            store: store,
            cap: settings.feedDownloadUnplayedSoftCap.episodeCap
        )
    }

    /// Unplayed, non-archived episodes on this feed only (for Mark all as played).
    /// Bulk Mark all as played always uses full-feed eligibility (not the filtered subset).
    private var markAllPlayedCandidates: [PodcastEpisode] {
        liveFeed.episodes.filter { !store.isPlayed($0.id) && !store.isArchived($0.id) }
    }

    /// Played episodes on this feed only (for Mark all as unplayed) — **includes archived**.
    /// Archive policy: prefer mark unplayed even if archived (Mark all as played skips archived;
    /// unplayed bulk still flips played archived). Full-feed eligibility (not chip/search).
    private var markAllUnplayedCandidates: [PodcastEpisode] {
        liveFeed.episodes.filter { store.isPlayed($0.id) }
    }

    /// Full feed episode catalog minus already queued — Add all to queue always uses this,
    /// **not** the chip/search filtered visible list (`filteredEpisodes`). Same full-feed
    /// honesty as Download all unplayed / Mark all as played / Mark all as unplayed /
    /// Add all unplayed to queue (eligibility not limited to visible filter).
    /// Confirm count and `enqueueAllFromFeed` share this eligibility (played/archived included).
    private var enqueueAllFromFeedCandidatesCount: Int {
        liveFeed.episodes.filter { !store.isInQueue($0.id) }.count
    }

    /// Unplayed, not archived, not already queued — Add all unplayed to queue always uses this
    /// full-feed eligibility (not chip/search). Order matches `enqueueAllUnplayedFromFeed`
    /// (effective episode sort). Confirm count and enqueue share this list.
    private var enqueueAllUnplayedFromFeedCandidates: [PodcastEpisode] {
        store.enqueueAllUnplayedFromFeedCandidates(liveFeed)
    }

    /// Completed Downloads catalog rows for this feed’s episode ids (same set as
    /// `DownloadService.deleteDownloads(forFeed:)`). Not chip/search filtered.
    private var unsubscribeFeedDownloadsCount: Int {
        downloads.downloads(forFeed: liveFeed).count
    }

    private var unsubscribeFeedDownloadsSizeLabel: String {
        DownloadStorageUsage.formatBytes(downloads.downloadsByteSize(forFeed: liveFeed))
    }

    /// Non-favorited completed Downloads for this feed (Feed detail **Delete downloads**).
    /// Skips favorites like auto-delete-after-playing / Downloads Delete played.
    /// Full-feed catalog via `downloadsEligibleForDelete(forFeed:)` — not chip/search filtered.
    private var deleteFeedDownloadsEligible: [DownloadedEpisode] {
        downloads.downloadsEligibleForDelete(forFeed: liveFeed, store: store)
    }

    private var deleteFeedDownloadsSizeLabel: String {
        DownloadStorageUsage.formatBytes(
            downloads.downloadsEligibleByteSize(forFeed: liveFeed, store: store)
        )
    }

    /// Favorited completed downloads for this feed that Delete downloads will **keep**.
    /// Shown in confirm for honesty when some favorites remain after eligible delete.
    private var deleteFeedDownloadsSkippedFavoritesCount: Int {
        max(0, downloads.downloads(forFeed: liveFeed).count - deleteFeedDownloadsEligible.count)
    }

    /// Non-archived episodes on this feed with playable media via shared `EpisodePlayRandom`
    /// (local file via `DownloadService.localURL` — downloads + local-folder `file://` — or
    /// streamable http(s) `downloadUrl`). Full-feed catalog — **not** chip/search filtered.
    /// Distinct from Download all unplayed / Mark all / Add all unplayed / Add all eligibility.
    private var playRandomEligibleEpisodes: [PodcastEpisode] {
        let catalog = liveFeed.episodes.filter { !store.isArchived($0.id) }
        return EpisodePlayRandom.eligible(
            from: catalog,
            localURL: { downloads.localURL(for: $0) }
        )
    }

    /// Prefer unplayed among `playRandomEligibleEpisodes` when any remain; otherwise all eligible
    /// (played allowed when every eligible episode is played, or none unplayed eligible).
    private var playRandomCandidates: [PodcastEpisode] {
        EpisodePlayRandom.candidates(
            from: playRandomEligibleEpisodes,
            preferUnplayed: true,
            isPlayed: { store.isPlayed($0) }
        )
    }

    var body: some View {
        List {
            if LocalFolderFeed.isLocalFolderFeed(liveFeed) {
                Section {
                    Label("Local folder feed", systemImage: "folder.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel(String(localized: "Local folder feed"))

                    Text("Episodes are audio files in a picked folder (\(LocalFolderFeed.audioFormatsDisplay); this folder only, not subfolders). No RSS and no network refresh. Podcasting 2.0 / iTunes feed tags do not apply. Omitted from OPML, HTML export, and gpodder sync. Unsubscribe releases folder access.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(String(localized: "Episodes are audio files in a picked folder. No RSS and no network refresh. Podcasting 2.0 tags do not apply. Omitted from OPML. Unsubscribe releases folder access."))

                    Button {
                        Task { await rescanLocalFolder() }
                    } label: {
                        if isRescanningLocalFolder {
                            Label("Rescanning…", systemImage: "arrow.clockwise")
                        } else {
                            Label("Rescan folder", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(isRescanningLocalFolder || store.isLoading)
                    .accessibilityLabel(String(localized: "Rescan folder"))
                    .accessibilityHint(String(localized: "Re-reads audio files in the folder via the saved bookmark. Does not fetch an RSS feed."))

                    if let err = store.lastError, LocalFolderFeed.isLocalFolderFeed(liveFeed) {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityLabel(err)
                    }
                } footer: {
                    Text("Swipe Refresh on Subscriptions also re-scans. Empty folders stay subscribed until you add files or unsubscribe.")
                }
            }
            if let author = displayAuthor {
                Section {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(String(localized: "Author \(author)"))
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Feed language when present (itunes:language / RSS language / xml:lang); hide when missing.
            if let language = displayLanguage {
                Section {
                    Text(language)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(String(localized: "Language \(language)"))
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Last successful network refresh — hide when nil / local-folder (Rescan is not a network refresh).
            if let lastRefreshedAt {
                Section {
                    LabeledContent(String(localized: "Last refreshed")) {
                        Text(lastRefreshedAt, style: .relative)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        String(
                            localized: "Last refreshed \(lastRefreshedAt.formatted(date: .abbreviated, time: .shortened))"
                        )
                    )
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Channel podcast:medium when present — raw feed string; hide when missing (never invent/remap; display-only).
            if let medium = displayMedium {
                Section {
                    Text(medium)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.2), in: Capsule())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(String(localized: "Medium \(medium)"))
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Channel itunes:type when present — Episodic/Serial (localized) or raw; hide when missing (never invent).
            // Capsule is display-only; Serial may one-shot set per-feed Oldest first when episodeSort is still nil.
            if let itunesType = displayItunesType {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(itunesType)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.2), in: Capsule())
                            .accessibilityLabel(liveFeed.itunesTypeAccessibilityLabel ?? itunesType)
                        if liveFeed.isItunesTypeSerial {
                            Text(String(localized: "Serial podcasts may use Oldest first once for narrative order when per-feed sort is unset. You can still pick any sort. The itunes:type capsule stays display-only."))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(String(localized: "Serial podcasts may use Oldest first once for narrative order when per-feed sort is unset. You can still pick any sort. The itunes:type capsule stays display-only."))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Channel podcast:updateFrequency when present — text + optional complete/rrule/dtstart; hide when missing (never invent; display-only — no Keep updated/refresh change).
            if let uf = displayUpdateFrequency {
                Section {
                    FeedUpdateFrequencyDetailBlock(frequency: uf)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Channel itunes:complete yes/true only — display-only Apple claim; distinct from podcast:updateFrequency complete; no Keep updated/refresh change.
            if liveFeed.isItunesComplete {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Complete"))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.2), in: Capsule())
                        Text(String(localized: "This podcast marks itunes:complete. The publisher claims no further episodes. This does not change Keep updated or refresh."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(liveFeed.itunesCompleteAccessibilityLabel)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Channel itunes:explicit only — hide when feed does not mark explicit (never invent).
            if liveFeed.isExplicit {
                Section {
                    Text(String(localized: "Explicit"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.2), in: Capsule())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(String(localized: "Explicit"))
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Channel podcast:locked=yes only — display-only claim; no owner verification / host block.
            if liveFeed.isLocked {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Locked"))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.2), in: Capsule())
                        Text(String(localized: "This feed claims to be locked for transfer. This app does not verify ownership."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let owner = liveFeed.displayLockedOwner {
                            Text(String(localized: "Locked owner \(owner)"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(feedLockedAccessibilityLabel)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Channel podcast:block / itunes:block yes/true — display-only directory metadata; distinct from podcast:locked; no subscribe/play block.
            if liveFeed.isBlocked {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Blocked"))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.2), in: Capsule())
                        Text(String(localized: "This feed marks podcast:block or itunes:block for directories. This app does not enforce it — subscribe and play still work."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(feedBlockedAccessibilityLabel)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Channel podcast:guid when present — display/copy/share only; never invent; distinct from episode guid.
            if let guid = displayPodcastGuid {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Podcast GUID"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(guid)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        HStack(spacing: 12) {
                            Button {
                                copyPodcastGuid()
                            } label: {
                                Label("Copy podcast GUID", systemImage: "doc.on.doc")
                                    .font(.subheadline)
                            }
                            .accessibilityLabel(String(localized: "Copy podcast GUID"))
                            .accessibilityHint(String(localized: "Copies the podcast GUID from the feed to the pasteboard"))

                            ShareLink(
                                item: guid,
                                subject: Text("\(feedDisplayTitle) — \(String(localized: "Podcast GUID"))"),
                                message: Text("\(feedDisplayTitle) — \(String(localized: "Podcast GUID"))")
                            ) {
                                Label("Share podcast GUID", systemImage: "square.and.arrow.up")
                                    .font(.subheadline)
                            }
                            .accessibilityLabel(String(localized: "Share podcast GUID"))
                            .accessibilityHint(
                                String(localized: "Shares the feed-provided podcast GUID as plain text; distinct from the podcast, feed URL, website, funding, and discussion shares")
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .contain)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Feed itunes:category chips (parent + nested text attrs); hide when none — never invent.
            if !displayCategories.isEmpty {
                Section {
                    FeedCategoryChips(categories: displayCategories)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            String(localized: "Categories \(displayCategories.joined(separator: ", "))")
                        )
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Channel podcast:person — name + role when set; http(s) href → system browser; hide when none.
            if !displayPeople.isEmpty {
                Section {
                    PodcastPeopleListView(people: displayPeople)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Channel podcast:location — name + optional rel/osm; Open in Maps when geo lat,lon; hide when none.
            // Feed-provided only — never invent names / never geocode.
            if !displayLocations.isEmpty {
                Section {
                    PodcastLocationsListView(locations: displayLocations)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Channel podcast:socialInteract — Discuss opens http(s) uri in system browser; hide when none / disabled.
            // Feed-provided only — never invent URLs; no in-app Fediverse client / posting.
            if !displaySocialInteracts.isEmpty {
                Section {
                    PodcastSocialInteractListView(socialInteracts: displaySocialInteracts)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Channel podcast:value / valueRecipient — Value / Support creators metadata; display-only (no Lightning sends).
            // http(s) address → Open in browser; else Copy. Hide when none — never invent recipients / payment addresses.
            if hasDisplayValueRecipients {
                Section {
                    PodcastValueRecipientsListView(values: displayValues)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Channel podcast:trailer — title + Play (enclosure-like http(s) via PlaybackService) or Open URL; hide when none.
            // Distinct from itunes:episodeType=trailer on items (EpisodeRow Trailer badge).
            if let trailer = displayTrailer {
                Section {
                    feedTrailerRow(trailer)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Channel podcast:liveItem — status/start/end/title + Open link/contentLink in browser; hide when none.
            // Display-only — no live stream player / recording / chat / payments. Never invent live items.
            if !displayLiveItems.isEmpty {
                Section {
                    PodcastLiveItemsListView(liveItems: displayLiveItems)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Channel podcast:txt — purpose (raw feed string) + text; Copy / Open http(s); hide when none.
            // Display-only — no Social / Matrix / special clients. Never invent purposes or text.
            if !displayTexts.isEmpty {
                Section {
                    PodcastTxtListView(texts: displayTexts)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Channel podcast:license — text + optional url; Open http(s) / Copy; hide when none.
            // Display-only — no DRM enforcement. Never invent licenses.
            if !displayLicenses.isEmpty {
                Section {
                    PodcastLicenseListView(licenses: displayLicenses)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Channel podcast:images / podcast:image — URL + optional width; Open / Copy; hide when none.
            // Prefer one higher-res URL for artwork elsewhere; do not download all variants here. Never invent.
            if !displayImages.isEmpty {
                Section {
                    PodcastImagesListView(images: displayImages)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Channel podcast:podroll / remoteItem — creator recommendations; Open / Copy / Subscribe preview; hide when none.
            // Display-only — never invent shows; no Podcast Index GUID resolution.
            if !displayPodrollItems.isEmpty {
                Section {
                    PodcastPodrollListView(items: displayPodrollItems)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Channel podcast:publisher / remoteItem — publisher feed link; Open / Copy / Subscribe preview; hide when none.
            // Display-only — never invent publishers; no Podcast Index GUID resolution. Cap 1.
            if !displayPublisherItems.isEmpty {
                Section {
                    PodcastPublisherListView(items: displayPublisherItems)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Local private note indicator — hide when empty; tap opens per-feed settings (uncrowded).
            if let note = feedPrivateNote {
                Section {
                    Button {
                        showPerFeedSettings = true
                    } label: {
                        Label {
                            Text(note)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } icon: {
                            Image(systemName: "note.text")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Private note"))
                    .accessibilityValue(note)
                    .accessibilityHint(String(localized: "Opens podcast settings to edit the local private note"))
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            if !feedTags.isEmpty {
                Section("Tags") {
                    FlowTagRow(tags: feedTags)
                    Button("Manage tags…") {
                        showPerFeedSettings = true
                    }
                }
            }
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(FeedEpisodeFilter.allCases) { chip in
                            FeedEpisodeFilterChip(
                                title: chip.label,
                                selected: settings.feedEpisodeFilter == chip
                            ) {
                                settings.feedEpisodeFilter = chip
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }

            // itunes:episodeType chips — hide when no known/unknown types in this feed catalog.
            if showFeedEpisodeTypeFilterChips {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(feedEpisodeTypeFilterChips) { chip in
                                FeedEpisodeFilterChip(
                                    title: chip.label,
                                    selected: settings.feedEpisodeTypeFilter == chip,
                                    accessibilityHint: String(localized: "Filters the Feed episodes list by episode type")
                                ) {
                                    settings.feedEpisodeTypeFilter = chip
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }

            // AntennaPod-like Feed detail info bar (visible sort→status→type→search list remaining time).
            // Distinct from Download all unplayed / Mark all as played / Mark all as unplayed / Add all unplayed to queue / Add all to queue / Delete downloads / Play random full-feed eligibility counts.
            if let remainingLabel = feedRemainingInfoLabel {
                Section {
                    Text(remainingLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(feedRemainingAccessibilityLabel)
                }
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
            }

            Section("Episodes") {
                if liveFeed.episodes.isEmpty {
                    if LocalFolderFeed.isLocalFolderFeed(liveFeed) {
                        ContentUnavailableView(
                            "No audio files",
                            systemImage: "folder",
                            description: Text("This folder has no \(LocalFolderFeed.audioFormatsDisplay) files yet (subfolders are not scanned). Add files in Files, then Rescan folder, or swipe Refresh on Subscriptions.")
                        )
                    } else {
                        ContentUnavailableView(
                            "No episodes",
                            systemImage: "list.bullet",
                            description: Text("This podcast has no episodes yet. Pull to refresh on Subscriptions.")
                        )
                    }
                } else if filteredEpisodes.isEmpty {
                    ContentUnavailableView(
                        "No matching episodes",
                        systemImage: "magnifyingglass",
                        description: Text(
                            isFiltering
                                ? String(localized: "No episodes match your filter.")
                                : String(localized: "No episodes match your search.")
                        )
                    )
                } else {
                    ForEach(filteredEpisodes) { episode in
                        EpisodeRow(episode: episode, feedTitle: feedDisplayTitle)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    store.togglePlayed(episode.id)
                                } label: {
                                    Label(
                                        store.isPlayed(episode.id)
                                            ? String(localized: "Mark unplayed")
                                            : String(localized: "Mark played"),
                                        systemImage: store.isPlayed(episode.id) ? "circle" : "checkmark.circle"
                                    )
                                }
                                .tint(.blue)
                                .accessibilityHint(
                                    store.isPlayed(episode.id)
                                        ? String(localized: "Marks this episode as unplayed")
                                        : String(localized: "Marks this episode as played")
                                )
                                Button {
                                    store.toggleArchived(episode.id)
                                } label: {
                                    Label(
                                        store.isArchived(episode.id) ? "Restore" : "Archive",
                                        systemImage: store.isArchived(episode.id) ? "arrow.uturn.backward" : "archivebox"
                                    )
                                }
                                .tint(store.isArchived(episode.id) ? .green : .orange)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    store.playNext(episode, currentlyPlayingId: playback.currentEpisode?.id)
                                } label: {
                                    Label("Play Next", systemImage: "text.insert")
                                }
                                .tint(.teal)
                                Button {
                                    store.enqueue(episode)
                                } label: {
                                    Label("Queue", systemImage: "text.append")
                                }
                                .tint(.purple)
                                if let url = episode.shareURL(feed: liveFeed) {
                                    ShareLink(
                                        item: url,
                                        subject: Text(episode.title),
                                        message: Text(episode.shareMessage(feedTitle: feedDisplayTitle))
                                    ) {
                                        Label("Share", systemImage: "square.and.arrow.up")
                                    }
                                    .tint(.indigo)
                                    .accessibilityLabel(String(localized: "Share episode"))
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle(feedDisplayTitle)
        .searchable(text: $searchText, prompt: "Search episodes")
        .onChange(of: searchText) { _, newValue in
            scheduleFilter(for: newValue)
        }
        .onDisappear {
            debounceTask?.cancel()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker(selection: feedEpisodeSortBinding) {
                        ForEach(FeedEpisodeSort.allCases) { sort in
                            Label(sort.label, systemImage: sort.systemImage)
                                .tag(sort)
                        }
                    } label: {
                        Text("Sort")
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .accessibilityLabel(String(localized: "Sort episodes"))
                .accessibilityValue(resolvedEpisodeSort.label)
                .accessibilityHint(String(localized: "Orders this podcast’s episode list. Saved per podcast. Serial may auto-set Oldest first once when unset; capsule stays display-only."))
            }
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    if hasReadableFeedDescription {
                        Button {
                            showFeedDescription = true
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .accessibilityLabel(String(localized: "Podcast description"))
                        .accessibilityHint(String(localized: "Opens the podcast description from the feed"))
                    }
                    if let url = liveFeed.shareURL {
                        ShareLink(
                            item: url,
                            subject: Text(feedDisplayTitle),
                            message: Text(feedDisplayTitle)
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(String(localized: "Share podcast"))
                    }
                    Menu {
                        if let url = liveFeed.websiteURL {
                            Button {
                                openURL(url)
                            } label: {
                                Label("Open podcast website", systemImage: "safari")
                            }
                            .accessibilityLabel(String(localized: "Open podcast website"))
                            .accessibilityHint(String(localized: "Opens the podcast webpage in the system browser"))

                            Button {
                                copyPodcastWebsiteURL(url)
                            } label: {
                                Label("Copy podcast website", systemImage: "doc.on.doc")
                            }
                            .accessibilityLabel(String(localized: "Copy podcast website"))
                            .accessibilityHint(
                                String(localized: "Copies the feed-provided podcast website URL to the pasteboard; distinct from the feed RSS URL and funding URL")
                            )

                            ShareLink(
                                item: url,
                                subject: Text(feedDisplayTitle),
                                message: Text(feedDisplayTitle)
                            ) {
                                Label("Share podcast website", systemImage: "square.and.arrow.up")
                            }
                            .accessibilityLabel(String(localized: "Share podcast website"))
                            .accessibilityHint(
                                String(localized: "Shares the feed-provided podcast website URL; distinct from the feed RSS URL and funding URL")
                            )
                        }

                        if let url = liveFeed.fundingURL {
                            Button {
                                openURL(url)
                            } label: {
                                Label(liveFeed.supportActionTitle, systemImage: "heart.circle")
                            }
                            .accessibilityLabel(liveFeed.supportAccessibilityLabel)
                            .accessibilityHint(
                                String(localized: "Opens the feed-provided funding/support page in the system browser; does not process payments")
                            )

                            Button {
                                copyFundingURL(url)
                            } label: {
                                Label("Copy funding URL", systemImage: "doc.on.doc")
                            }
                            .accessibilityLabel(String(localized: "Copy funding URL"))
                            .accessibilityHint(
                                String(localized: "Copies the feed-provided funding/support page URL to the pasteboard; does not process payments")
                            )

                            ShareLink(
                                item: url,
                                subject: Text(feedDisplayTitle),
                                message: Text("\(feedDisplayTitle) — \(liveFeed.supportActionTitle)")
                            ) {
                                Label("Share funding URL", systemImage: "square.and.arrow.up")
                            }
                            .accessibilityLabel(String(localized: "Share funding URL"))
                            .accessibilityHint(
                                String(localized: "Shares the feed-provided funding/support page URL; does not process payments")
                            )
                        }

                        if let interact = liveFeed.preferredSocialInteract,
                           let url = interact.discussionURL {
                            Button {
                                openURL(url)
                            } label: {
                                Label("Discuss", systemImage: "bubble.left.and.bubble.right")
                            }
                            .accessibilityLabel(String(localized: "Discuss"))
                            .accessibilityHint(String(localized: "Opens the discussion link from the feed in the system browser"))

                            Button {
                                copyDiscussURL(url)
                            } label: {
                                Label("Copy discuss URL", systemImage: "doc.on.doc")
                            }
                            .accessibilityLabel(String(localized: "Copy discuss URL"))
                            .accessibilityHint(
                                String(localized: "Copies the feed-provided discussion URL to the pasteboard; does not post as you")
                            )

                            ShareLink(
                                item: url,
                                subject: Text(feedDisplayTitle),
                                message: Text("\(feedDisplayTitle) — Discuss")
                            ) {
                                Label("Share discuss URL", systemImage: "square.and.arrow.up")
                            }
                            .accessibilityLabel(String(localized: "Share discuss URL"))
                            .accessibilityHint(
                                String(localized: "Shares the feed-provided discussion URL; opens only and does not post as you")
                            )
                        }

                        Button {
                            copyFeedURL()
                        } label: {
                            Label("Copy feed URL", systemImage: "doc.on.doc")
                        }
                        .disabled(!canCopyFeedURL)
                        .accessibilityLabel(String(localized: "Copy feed URL"))

                        if let url = feedURLShareURL {
                            ShareLink(
                                item: url,
                                subject: Text("\(feedDisplayTitle) — Feed URL"),
                                message: Text("\(feedDisplayTitle) — Feed URL")
                            ) {
                                Label("Share feed URL", systemImage: "square.and.arrow.up")
                            }
                            .disabled(!canCopyFeedURL)
                            .accessibilityLabel(String(localized: "Share feed URL"))
                            .accessibilityHint(
                                String(localized: "Shares the feed RSS or Atom URL; distinct from the podcast website, funding, and discussion links")
                            )
                        } else {
                            ShareLink(
                                item: feedURLShareString,
                                subject: Text("\(feedDisplayTitle) — Feed URL"),
                                message: Text("\(feedDisplayTitle) — Feed URL")
                            ) {
                                Label("Share feed URL", systemImage: "square.and.arrow.up")
                            }
                            .disabled(!canCopyFeedURL)
                            .accessibilityLabel(String(localized: "Share feed URL"))
                            .accessibilityHint(
                                String(localized: "Shares the raw feed URL; distinct from the podcast website, funding, and discussion links")
                            )
                        }

                        if let guid = displayPodcastGuid {
                            Button {
                                copyPodcastGuid()
                            } label: {
                                Label("Copy podcast GUID", systemImage: "number")
                            }
                            .accessibilityLabel(String(localized: "Copy podcast GUID"))
                            .accessibilityHint(String(localized: "Copies the podcast GUID from the feed to the pasteboard"))

                            ShareLink(
                                item: guid,
                                subject: Text("\(feedDisplayTitle) — \(String(localized: "Podcast GUID"))"),
                                message: Text("\(feedDisplayTitle) — \(String(localized: "Podcast GUID"))")
                            ) {
                                Label("Share podcast GUID", systemImage: "square.and.arrow.up")
                            }
                            .accessibilityLabel(String(localized: "Share podcast GUID"))
                            .accessibilityHint(
                                String(localized: "Shares the feed-provided podcast GUID as plain text; distinct from the podcast, feed URL, website, funding, and discussion shares")
                            )
                        }

                        Button {
                            playRandomEpisode()
                        } label: {
                            Label("Play random", systemImage: "shuffle")
                        }
                        .disabled(playRandomCandidates.isEmpty)
                        .accessibilityLabel(String(localized: "Play random"))
                        .accessibilityHint(String(localized: "Plays a random non-archived episode from this podcast. Prefers unplayed when any remain."))

                        Button {
                            store.togglePinned(feedId: liveFeed.id)
                        } label: {
                            if store.isPinned(feedId: liveFeed.id) {
                                Label("Don’t keep at top", systemImage: "pin.slash")
                            } else {
                                Label("Keep at top", systemImage: "pin")
                            }
                        }
                        .accessibilityLabel(
                            store.isPinned(feedId: liveFeed.id)
                                ? String(localized: "Don’t keep at top")
                                : String(localized: "Keep at top")
                        )
                        .accessibilityHint(String(localized: "Pins or unpins this podcast at the top of the Subscriptions list"))

                        Button {
                            showDownloadAllConfirm = true
                        } label: {
                            Label("Download all unplayed", systemImage: "arrow.down.circle")
                        }
                        .disabled(downloadAllCandidates.isEmpty)
                        .accessibilityLabel(String(localized: "Download all unplayed"))
                        .accessibilityHint(String(localized: "Queues downloads for unplayed episodes in this podcast that are not archived and not already downloaded"))

                        Button {
                            showMarkAllPlayedConfirm = true
                        } label: {
                            Label("Mark all as played", systemImage: "checkmark.circle")
                        }
                        .disabled(markAllPlayedCandidates.isEmpty)

                        Button {
                            showMarkAllUnplayedConfirm = true
                        } label: {
                            Label("Mark all as unplayed", systemImage: "circle")
                        }
                        .disabled(markAllUnplayedCandidates.isEmpty)
                        .accessibilityHint(String(localized: "Marks played episodes in this podcast as unplayed, including archived"))

                        Button {
                            showEnqueueAllUnplayedConfirm = true
                        } label: {
                            Label("Add all unplayed to queue", systemImage: "text.badge.plus")
                        }
                        .disabled(enqueueAllUnplayedFromFeedCandidates.isEmpty)
                        .accessibilityLabel(String(localized: "Add all unplayed to queue"))
                        .accessibilityHint(String(localized: "Appends unplayed episodes in this podcast that are not archived and not already queued, in episode sort order"))

                        Button {
                            showEnqueueAllConfirm = true
                        } label: {
                            Label("Add all to queue", systemImage: "text.append")
                        }
                        .disabled(enqueueAllFromFeedCandidatesCount == 0)
                        .accessibilityHint(String(localized: "Appends all feed episodes not already queued, including played and archived"))

                        Button(role: .destructive) {
                            showDeleteDownloadsConfirm = true
                        } label: {
                            Label("Delete downloads", systemImage: "externaldrive.badge.minus")
                        }
                        .disabled(deleteFeedDownloadsEligible.isEmpty)
                        .accessibilityHint(String(localized: "Deletes this podcast’s offline files except favorites; keeps played status, queue, and archive"))

                        Button(role: .destructive) {
                            showUnsubscribeConfirm = true
                        } label: {
                            Label("Unsubscribe", systemImage: "trash")
                        }
                        .accessibilityHint(String(localized: "Opens unsubscribe confirmation; optional delete this feed’s downloads"))
                    } label: {
                        Label("Feed actions", systemImage: "ellipsis.circle")
                    }
                    Button {
                        showPerFeedSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(String(localized: "Podcast settings"))
                }
            }
        }
        .confirmationDialog(
            "Download all unplayed?",
            isPresented: $showDownloadAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Download all unplayed") {
                let episodes = downloadAllCandidates
                Task {
                    await downloads.downloadAllManual(episodes)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Queues download of \(downloadAllCandidates.count) unplayed episodes (newest first, max \(settings.feedDownloadUnplayedSoftCap.episodeCap)). Played, archived, already downloaded, and local-folder files are skipped. Requires http(s) enclosure. Uses the full feed catalog — not the chip or search filter. Manual download Wi‑Fi only, parallel-download cap, and storage limit still apply."
            )
        }
        .confirmationDialog(
            "Mark all as played?",
            isPresented: $showMarkAllPlayedConfirm,
            titleVisibility: .visible
        ) {
            Button("Mark all as played") {
                store.markAllPlayed(inFeedId: liveFeed.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Marks \(markAllPlayedCandidates.count) unplayed episodes in this podcast as played. Does not archive; auto-delete after playing still applies when enabled."
            )
        }
        .confirmationDialog(
            "Mark all as unplayed?",
            isPresented: $showMarkAllUnplayedConfirm,
            titleVisibility: .visible
        ) {
            Button("Mark all as unplayed") {
                store.markAllUnplayed(inFeedId: liveFeed.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Marks \(markAllUnplayedCandidates.count) played episodes in this podcast as unplayed (including archived). Does not delete downloads, remove from queue, stop playback, or unarchive."
            )
        }
        .confirmationDialog(
            "Add all unplayed to queue?",
            isPresented: $showEnqueueAllUnplayedConfirm,
            titleVisibility: .visible
        ) {
            Button("Add all unplayed to queue") {
                store.enqueueAllUnplayedFromFeed(liveFeed)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Appends \(enqueueAllUnplayedFromFeedCandidates.count) unplayed episodes from this podcast to the end of the queue in this podcast’s episode sort order (per-feed or global). Played, archived, and already queued episodes are skipped. Uses the full feed episode catalog (same honesty as Download all unplayed / Mark all as played), not the chip or search filter. Queue lock does not block enqueue."
            )
        }
        .confirmationDialog(
            "Add all to queue?",
            isPresented: $showEnqueueAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Add all to queue") {
                store.enqueueAllFromFeed(liveFeed)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Appends \(enqueueAllFromFeedCandidatesCount) episodes from this podcast to the end of the queue (newest publish date first). Already queued episodes are skipped. Uses the full feed episode catalog (same honesty as Download all unplayed / Mark all as played), not the chip or search filter. Includes played and archived. Queue lock does not block enqueue. Distinct from Add all unplayed to queue."
            )
        }
        .confirmationDialog(
            "Delete downloads?",
            isPresented: $showDeleteDownloadsConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete downloads", role: .destructive) {
                downloads.deleteEligibleDownloads(forFeed: liveFeed, store: store)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if deleteFeedDownloadsSkippedFavoritesCount > 0 {
                Text(
                    "Deletes \(deleteFeedDownloadsEligible.count) offline file(s) for this podcast (\(deleteFeedDownloadsSizeLabel)). Skips \(deleteFeedDownloadsSkippedFavoritesCount) favorited download(s). Local files only — keeps played status, queue, favorites, and archive. Distinct from Unsubscribe, Delete played downloads, and Clear all downloads."
                )
            } else {
                Text(
                    "Deletes \(deleteFeedDownloadsEligible.count) offline file(s) for this podcast (\(deleteFeedDownloadsSizeLabel)). Skips favorited downloads. Local files only — keeps played status, queue, favorites, and archive. Distinct from Unsubscribe, Delete played downloads, and Clear all downloads."
                )
            }
        }
        .confirmationDialog(
            "Unsubscribe?",
            isPresented: $showUnsubscribeConfirm,
            titleVisibility: .visible
        ) {
            Button("Unsubscribe", role: .destructive) {
                store.unsubscribe(liveFeed)
                dismiss()
            }
            if unsubscribeFeedDownloadsCount > 0 {
                Button(
                    "Unsubscribe and delete \(unsubscribeFeedDownloadsCount) downloads (\(unsubscribeFeedDownloadsSizeLabel))",
                    role: .destructive
                ) {
                    downloads.deleteDownloads(forFeed: liveFeed)
                    store.unsubscribe(liveFeed)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if unsubscribeFeedDownloadsCount > 0 {
                Text(
                    "Unsubscribe from \"\(feedDisplayTitle)\"? Removes this podcast from Subscriptions, its feed settings and tags, queue items from this feed, and favorites, archive, and playback history for its episodes. This feed has \(unsubscribeFeedDownloadsCount) offline download(s) (\(unsubscribeFeedDownloadsSizeLabel)). Unsubscribe keeps those files; Unsubscribe and delete downloads removes only this feed’s offline files (incl. favorited). Does not clear other podcasts’ downloads or Clear all downloads."
                )
            } else {
                Text(
                    "Unsubscribe from \"\(feedDisplayTitle)\"? Removes this podcast from Subscriptions, its feed settings and tags, queue items from this feed, and favorites, archive, and playback history for its episodes. Downloaded files are kept."
                )
            }
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showFeedURLCopied
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "Feed URL copied to the pasteboard."))
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showFundingURLCopied
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "Funding URL copied to the pasteboard."))
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showPodcastWebsiteURLCopied
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "Podcast website URL copied to the pasteboard."))
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showPodcastGuidCopied
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "Podcast GUID copied to the pasteboard."))
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showDiscussURLCopied
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "Discuss URL copied to the pasteboard."))
        }
        .sensoryFeedback(.success, trigger: copyFeedURLFeedbackTick)
        .sensoryFeedback(.success, trigger: copyFundingURLFeedbackTick)
        .sensoryFeedback(.success, trigger: copyPodcastWebsiteURLFeedbackTick)
        .sensoryFeedback(.success, trigger: copyPodcastGuidFeedbackTick)
        .sensoryFeedback(.success, trigger: copyDiscussURLFeedbackTick)
        .sheet(isPresented: $showPerFeedSettings) {
            NavigationStack {
                PerFeedSettingsView(feedId: feed.id, feedTitle: feedDisplayTitle)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showPerFeedSettings = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showFeedDescription) {
            FeedDescriptionSheetView(feed: liveFeed, displayTitle: feedDisplayTitle)
                .environmentObject(store)
        }
        .safeAreaInset(edge: .bottom) {
            if let error = downloads.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(.ultraThinMaterial)
            }
        }
    }


    /// Re-scan the security-scoped folder (same path as Subscriptions Refresh swipe).
    @MainActor
    private func rescanLocalFolder() async {
        guard LocalFolderFeed.isLocalFolderFeed(liveFeed) else { return }
        isRescanningLocalFolder = true
        defer { isRescanningLocalFolder = false }
        await store.refresh(liveFeed)
    }

    /// Network RSS/Atom feeds only — local-folder feeds use a synthetic `local-folder://` id, not a pasteable feed URL.
    private var canCopyFeedURL: Bool {
        let trimmed = liveFeed.feedUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !LocalFolderFeed.isLocalFolderFeed(liveFeed)
    }

    private var feedURLShareString: String {
        liveFeed.feedUrl.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Share as a URL only for parseable HTTP(S); preserve other feed strings as raw text.
    private var feedURLShareURL: URL? {
        guard canCopyFeedURL, let url = URL(string: feedURLShareString) else { return nil }
        let scheme = url.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    private func copyFeedURL() {
        guard canCopyFeedURL else { return }
        let trimmed = liveFeed.feedUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        UIPasteboard.general.string = trimmed
        copyFeedURLFeedbackTick += 1
        showFeedURLCopied = true
    }

    private func copyFundingURL(_ url: URL) {
        UIPasteboard.general.string = url.absoluteString
        copyFundingURLFeedbackTick += 1
        showFundingURLCopied = true
    }

    private func copyPodcastWebsiteURL(_ url: URL) {
        UIPasteboard.general.string = url.absoluteString
        copyPodcastWebsiteURLFeedbackTick += 1
        showPodcastWebsiteURLCopied = true
    }

    private func copyDiscussURL(_ url: URL) {
        UIPasteboard.general.string = url.absoluteString
        copyDiscussURLFeedbackTick += 1
        showDiscussURLCopied = true
    }

    /// Feed-provided Podcast Index `podcast:guid` only — never invent / never derive from feed URL.
    private func copyPodcastGuid() {
        guard let guid = displayPodcastGuid else { return }
        UIPasteboard.general.string = guid
        copyPodcastGuidFeedbackTick += 1
        showPodcastGuidCopied = true
    }

    /// Channel podcast:trailer row — title (+ optional season); Play via PlaybackService when enclosure-like, else openURL.
    @ViewBuilder
    private func feedTrailerRow(_ trailer: PodcastTrailer) -> some View {
        let title = trailer.displayTitle ?? trailer.title
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Trailer"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let season = trailer.season {
                Text(String(localized: "Season \(season)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if trailer.prefersInAppPlayback {
                Button {
                    playOrOpenTrailer(trailer)
                } label: {
                    Label("Play trailer", systemImage: "play.fill")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Play trailer"))
                .accessibilityHint(String(localized: "Plays the podcast trailer from the feed"))
            } else if trailer.mediaURL != nil {
                Button {
                    playOrOpenTrailer(trailer)
                } label: {
                    Label("Open trailer", systemImage: "safari")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Open trailer"))
                .accessibilityHint(String(localized: "Opens the trailer URL in the system browser"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    /// Prefer in-app play for enclosure-like http(s) media; fall back to system browser for other http(s).
    /// Uses `fromBeginning: true` so feed skip-intro does not clip the trailer.
    private func playOrOpenTrailer(_ trailer: PodcastTrailer) {
        if trailer.prefersInAppPlayback,
           let episode = trailer.asPlaybackEpisode(feedId: liveFeed.id) {
            if playback.play(episode: episode, fromBeginning: true) {
                return
            }
        }
        if let url = trailer.mediaURL {
            openURL(url)
        }
    }


    /// Uniform pick via shared `EpisodePlayRandom.pick` among eligible (prefer unplayed);
    /// starts via `PlaybackService.play` (resume rules unchanged).
    /// No confirm; does not invent queue mutations beyond what `play` already does.
    private func playRandomEpisode() {
        guard let episode = EpisodePlayRandom.pick(
            from: playRandomEligibleEpisodes,
            preferUnplayed: true,
            isPlayed: { store.isPlayed($0) }
        ) else { return }
        _ = playback.play(episode: episode)
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




/// Filter chip for Feed detail status / itunes:episodeType rows (mirrors Downloads / All Episodes).
private struct FeedEpisodeFilterChip: View {
    let title: String
    let selected: Bool
    var accessibilityHint: String = String(localized: "Filters the Feed episodes list")
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

/// Wrapping itunes:category chips (Feed detail / description). Feed text only — no taxonomy mapping.
private struct FeedCategoryChips: View {
    let categories: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(categories, id: \.self) { name in
                Text(name)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .accessibilityLabel(String(localized: "Category \(name)"))
            }
        }
    }
}

/// Simple wrapping tag chips (Feed detail header).
private struct FlowTagRow: View {
    let tags: [String]

    var body: some View {
        // LazyVGrid keeps layout simple without a custom flow layout.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
        }
    }
}

struct EpisodeRow: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var downloads: DownloadService
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openURL) private var openURL
    let episode: PodcastEpisode
    let feedTitle: String
    /// When set (e.g. History last-played), shown instead of the episode pub date.
    var dateOverride: Date? = nil
    var dateAccessibilityLabel: String? = nil

    @State private var showDescription = false
    @State private var showEpisodePrivateNote = false
    @State private var showCopiedAlert = false
    @State private var copiedAlertMessage = ""
    @State private var copyURLFeedbackTick = 0

    private var state: EpisodePlaybackState {
        store.playbackState(for: episode.id)
    }

    /// Index in the persisted queue, or `nil` when not queued (drives Move to top/bottom visibility).
    private var queueIndex: Int? {
        store.queue.firstIndex(where: { $0.id == episode.id })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(episode.title)
                        .font(.headline)
                    Spacer(minLength: 8)
                    // itunes:explicit yes/true/explicit (item or inherited channel) — hide otherwise.
                    if episode.isExplicit {
                        Text(String(localized: "Explicit"))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2), in: Capsule())
                            .accessibilityHidden(true)
                    }
                    // Item podcast:medium raw string when set — hide when missing (never invent/remap; display-only).
                    if let medium = episode.displayMedium {
                        Text(medium)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2), in: Capsule())
                            .accessibilityHidden(true)
                    }
                    // itunes:episodeType — Full/Trailer/Bonus localized or raw; hide when missing (never invent; ≠ channel podcast:trailer).
                    if let episodeType = episode.displayEpisodeType {
                        Text(episodeType)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2), in: Capsule())
                            .accessibilityHidden(true)
                    }
                    if store.isFavorite(episode.id) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                    }
                    if store.hasEpisodePrivateNote(for: episode.id) {
                        Image(systemName: "note.text")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(String(localized: "Private note"))
                    }
                    if store.isArchived(episode.id) {
                        Image(systemName: "archivebox.fill")
                            .foregroundStyle(.orange)
                    }
                    if state.isPlayed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                if !feedTitle.isEmpty {
                    Text(feedTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if seasonEpisodeCaptionText != nil
                    || dateOverride != nil
                    || episode.pubDateEpochMs != nil
                    || formattedKnownDuration != nil
                    || formattedKnownByteSize != nil {
                    HStack(spacing: 6) {
                        if let seasonEpisodeCaptionText {
                            Text(seasonEpisodeCaptionText)
                                .monospacedDigit()
                        }
                        if let dateOverride {
                            // History / Favorites / Archived: live relative (hours matter).
                            if seasonEpisodeCaptionText != nil {
                                Text("·")
                                    .accessibilityHidden(true)
                            }
                            Text(dateOverride, style: .relative)
                        } else if let caption = formattedPubDateCaption {
                            // Publish date: Today / Yesterday / N days ago / absolute.
                            if seasonEpisodeCaptionText != nil {
                                Text("·")
                                    .accessibilityHidden(true)
                            }
                            Text(caption)
                        }
                        if let formattedKnownDuration {
                            if seasonEpisodeCaptionText != nil
                                || dateOverride != nil
                                || episode.pubDateEpochMs != nil {
                                Text("·")
                                    .accessibilityHidden(true)
                            }
                            Text(formattedKnownDuration)
                                .monospacedDigit()
                        }
                        if let formattedKnownByteSize {
                            if seasonEpisodeCaptionText != nil
                                || dateOverride != nil
                                || episode.pubDateEpochMs != nil
                                || formattedKnownDuration != nil {
                                Text("·")
                                    .accessibilityHidden(true)
                            }
                            Text(formattedKnownByteSize)
                                .monospacedDigit()
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                // AntennaPod-like: thin bar only for started-not-finished (position > 1, not isPlayed, duration known).
                if progressFraction > 0 {
                    ProgressView(value: progressFraction)
                        .tint(.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(episodeAccessibilityLabel)
            .accessibilityAddTraits(.isStaticText)

            HStack {
                Button {
                    playback.play(episode: episode)
                } label: {
                    Label(resumeLabel, systemImage: "play.fill")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(resumeLabel)
                .accessibilityAddTraits(.startsMediaSession)

                Button {
                    Task { await downloads.download(episode) }
                } label: {
                    if downloads.inProgress.contains(episode.id) {
                        ProgressView()
                    } else if downloads.isDownloaded(episode) {
                        Label("Downloaded", systemImage: "checkmark.circle.fill")
                    } else {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(episode.downloadUrl == nil || downloads.inProgress.contains(episode.id))
                .accessibilityLabel(downloadAccessibilityLabel)

                Button {
                    store.enqueue(episode)
                } label: {
                    Label("Queue", systemImage: "text.append")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(String(localized: "Queue"))

                Button {
                    store.togglePlayed(episode.id)
                } label: {
                    Label(
                        state.isPlayed ? "Mark unplayed" : "Mark played",
                        systemImage: state.isPlayed ? "circle" : "checkmark.circle"
                    )
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(
                    state.isPlayed
                        ? String(localized: "Mark unplayed")
                        : String(localized: "Mark played")
                )
                .accessibilityHint(
                    state.isPlayed
                        ? String(localized: "Marks this episode as unplayed")
                        : String(localized: "Marks this episode as played")
                )

                Button {
                    store.toggleFavorite(episode.id)
                } label: {
                    Label(
                        store.isFavorite(episode.id) ? "Unfavorite" : "Favorite",
                        systemImage: store.isFavorite(episode.id) ? "star.fill" : "star"
                    )
                }
                .buttonStyle(.bordered)
                .tint(store.isFavorite(episode.id) ? .yellow : nil)
                .accessibilityLabel(
                    store.isFavorite(episode.id)
                        ? String(localized: "Remove from favorites")
                        : String(localized: "Add to favorites")
                )

                Button {
                    store.toggleArchived(episode.id)
                } label: {
                    Label(
                        store.isArchived(episode.id) ? "Restore" : "Archive",
                        systemImage: store.isArchived(episode.id) ? "archivebox.fill" : "archivebox"
                    )
                }
                .buttonStyle(.bordered)
                .tint(store.isArchived(episode.id) ? .orange : nil)
                .accessibilityLabel(
                    store.isArchived(episode.id)
                        ? String(localized: "Restore")
                        : String(localized: "Archive")
                )
                .accessibilityHint(
                    store.isArchived(episode.id)
                        ? String(localized: "Restores this episode from the archive")
                        : String(localized: "Hides this episode from Inbox without marking it played")
                )

                episodeShareControl
            }
            .labelStyle(.iconOnly)
        }
        .padding(.vertical, 4)
        .opacity(store.isArchived(episode.id) ? 0.55 : 1)
        .contextMenu {
            Button {
                playback.playFromBeginning(episode: episode)
            } label: {
                Label("Play from beginning", systemImage: "backward.end.fill")
            }
            .accessibilityLabel(String(localized: "Play from beginning"))
            .accessibilityHint(String(localized: "Loads this episode from the start and plays"))

            if let url = episode.websiteURL {
                Button {
                    openURL(url)
                } label: {
                    Label("Open episode website", systemImage: "safari")
                }
                .accessibilityLabel(String(localized: "Open episode website"))
                .accessibilityHint(String(localized: "Opens the episode webpage in the system browser"))

                Button {
                    copyEpisodeLink(url)
                } label: {
                    Label("Copy episode link", systemImage: "doc.on.doc")
                }
                .accessibilityLabel(String(localized: "Copy episode link"))
                .accessibilityHint(String(localized: "Copies the episode webpage URL to the pasteboard"))
            }
            if let rawMediaURL = episode.mediaURLString {
                Button {
                    copyMediaURL(rawMediaURL)
                } label: {
                    Label("Copy media URL", systemImage: "link")
                }
                .accessibilityLabel(String(localized: "Copy media URL"))
                .accessibilityHint(String(localized: "Copies the episode media / enclosure URL to the pasteboard"))

                EpisodeShareLinks.mediaURLLabelStyle(episode: episode)
            }
            if let url = episodeShareURL {
                ShareLink(
                    item: url,
                    subject: Text(episode.title),
                    message: Text(episodeShareMessage)
                ) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel(String(localized: "Share episode"))
            }
            Button {
                store.toggleFavorite(episode.id)
            } label: {
                Label(
                    store.isFavorite(episode.id) ? "Unfavorite" : "Favorite",
                    systemImage: store.isFavorite(episode.id) ? "star.slash" : "star"
                )
            }
            .accessibilityLabel(
                store.isFavorite(episode.id)
                    ? String(localized: "Remove from favorites")
                    : String(localized: "Add to favorites")
            )
            Button {
                store.toggleArchived(episode.id)
            } label: {
                Label(
                    store.isArchived(episode.id) ? "Restore" : "Archive",
                    systemImage: store.isArchived(episode.id) ? "arrow.uturn.backward" : "archivebox"
                )
            }
            Button {
                store.togglePlayed(episode.id)
            } label: {
                Label(
                    state.isPlayed ? "Mark unplayed" : "Mark played",
                    systemImage: state.isPlayed ? "circle" : "checkmark.circle"
                )
            }
            Button {
                store.playNext(episode, currentlyPlayingId: playback.currentEpisode?.id)
            } label: {
                Label("Play Next", systemImage: "text.insert")
            }
            Button {
                store.enqueue(episode)
            } label: {
                Label("Add to queue", systemImage: "text.append")
            }
            // Move to top/bottom = manual reorder; hidden when Queue lock is on (Play Next / enqueue stay).
            if let qi = queueIndex, !settings.queueLocked {
                if qi > 0 {
                    Button {
                        store.moveQueueItemToTop(episode)
                    } label: {
                        Label("Move to top", systemImage: "arrow.up.to.line")
                    }
                    .accessibilityLabel(String(localized: "Move to top"))
                    .accessibilityHint(String(localized: "Places this episode at the start of the queue"))
                }
                if qi < store.queue.count - 1 {
                    Button {
                        store.moveQueueItemToBottom(episode)
                    } label: {
                        Label("Move to bottom", systemImage: "arrow.down.to.line")
                    }
                    .accessibilityLabel(String(localized: "Move to bottom"))
                    .accessibilityHint(String(localized: "Places this episode at the end of the queue"))
                }
            }
            Button {
                showEpisodePrivateNote = true
            } label: {
                Label(
                    String(localized: "Private note…"),
                    systemImage: store.hasEpisodePrivateNote(for: episode.id) ? "note.text" : "square.and.pencil"
                )
            }
            .accessibilityLabel(String(localized: "Private note"))
            .accessibilityHint(String(localized: "Opens the private note editor for this episode"))
            Button {
                showDescription = true
            } label: {
                Label("Shownotes", systemImage: "doc.text")
            }
        }
        .sheet(isPresented: $showDescription) {
            EpisodeDescriptionSheetView(episode: episode, feedTitle: feedTitle)
        }
        .sheet(isPresented: $showEpisodePrivateNote) {
            EpisodePrivateNoteSheet(episodeId: episode.id)
                .environmentObject(store)
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showCopiedAlert
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(copiedAlertMessage)
        }
        .sensoryFeedback(.success, trigger: copyURLFeedbackTick)
    }

    private func copyEpisodeLink(_ url: URL) {
        copiedAlertMessage = EpisodeCopyLinks.copyEpisodeLink(url)
        copyURLFeedbackTick += 1
        showCopiedAlert = true
    }

    private func copyMediaURL(_ rawURL: String) {
        copiedAlertMessage = EpisodeCopyLinks.copyMediaURL(rawURL)
        copyURLFeedbackTick += 1
        showCopiedAlert = true
    }

    private var resolvedFeed: PodcastFeed? {
        store.feed(containingEpisodeId: episode.id)
    }

    private var episodeShareURL: URL? {
        episode.shareURL(feed: resolvedFeed)
    }

    private var episodeShareMessage: String {
        episode.shareMessage(feedTitle: feedTitle.isEmpty ? resolvedFeed?.title : feedTitle)
    }

    @ViewBuilder
    private var episodeShareControl: some View {
        if let url = episodeShareURL {
            ShareLink(
                item: url,
                subject: Text(episode.title),
                message: Text(episodeShareMessage)
            ) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(String(localized: "Share episode"))
            .accessibilityHint(String(localized: "Opens the system share sheet with the episode title and link"))
        } else {
            Button {} label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .disabled(true)
            .accessibilityLabel(String(localized: "Share episode"))
            .accessibilityHint(String(localized: "No shareable link for this episode"))
        }
    }

    /// Fraction of episode heard for the thin list ProgressView.
    /// Position + duration from `playback.json` (`EpisodePlaybackState`); duration may fall back
    /// to feed `itunes:duration` / media via `knownDurationSeconds` when playback duration is unset.
    /// Hidden (0) when unplayed (`position ≤ 1`), fully played (`isPlayed`), or duration unknown.
    private var progressFraction: Double {
        guard !state.isPlayed else { return 0 }
        let position = state.positionSeconds
        // Match Resume / Continue listening: ignore sub-second noise.
        guard position > 1, let duration = knownDurationSeconds, duration > 0 else {
            return 0
        }
        return min(1, position / duration)
    }

    /// Remaining wall-clock seconds when in-progress with known duration; else `nil`.
    private var remainingSeconds: Double? {
        guard progressFraction > 0, let duration = knownDurationSeconds else { return nil }
        let left = duration - state.positionSeconds
        guard left.isFinite, left > 0 else { return nil }
        return left
    }

    private var resumeLabel: String {
        if !state.isPlayed, state.positionSeconds > 1 {
            return String(localized: "Resume")
        }
        return String(localized: "Play")
    }

    private var downloadAccessibilityLabel: String {
        if downloads.inProgress.contains(episode.id) {
            return String(localized: "Downloading")
        }
        if downloads.isDownloaded(episode) {
            return String(localized: "Downloaded")
        }
        return String(localized: "Download")
    }

    /// VoiceOver summary: title, feed, Explicit when marked, season/episode, type, date, duration, size, played / percent (+ remaining) or position-only, downloaded (+ favorite/archived).
    private var episodeAccessibilityLabel: String {
        var parts: [String] = [episode.title]
        if !feedTitle.isEmpty {
            parts.append(feedTitle)
        }
        if episode.isExplicit {
            parts.append(String(localized: "Explicit"))
        }
        if let medium = episode.displayMedium {
            parts.append(String(localized: "Medium \(medium)"))
        }
        if let seasonA11y = episode.seasonEpisodeAccessibilityLabel {
            parts.append(seasonA11y)
        }
        if let typeA11y = episode.episodeTypeAccessibilityLabel {
            parts.append(typeA11y)
        }
        if let dateOverride, let custom = dateAccessibilityLabel {
            parts.append(custom)
        } else if let caption = formattedPubDateCaption {
            parts.append(caption)
        }
        if let formattedKnownDuration {
            parts.append(String(localized: "Duration \(formattedKnownDuration)"))
        }
        if let formattedKnownByteSize {
            parts.append(String(localized: "Size \(formattedKnownByteSize)"))
        }
        if state.isPlayed {
            parts.append(String(localized: "Played"))
        } else if progressFraction > 0 {
            let pct = Int((progressFraction * 100).rounded())
            parts.append(String(localized: "\(pct) percent played"))
            if let remaining = remainingSeconds,
               let formatted = PodcastEpisode.formatPlaybackPosition(remaining) {
                parts.append(String(localized: "\(formatted) remaining"))
            }
        } else if !state.isPlayed, state.positionSeconds > 1 {
            // Duration unknown: no bar, but VoiceOver can still say saved position.
            if let formatted = PodcastEpisode.formatPlaybackPosition(state.positionSeconds) {
                parts.append(String(localized: "At \(formatted)"))
            }
        }
        if downloads.isDownloaded(episode) {
            parts.append(String(localized: "Downloaded"))
        } else if downloads.inProgress.contains(episode.id) {
            parts.append(String(localized: "Downloading"))
        }
        if store.isFavorite(episode.id) {
            parts.append(String(localized: "Favorite"))
        }
        if store.isArchived(episode.id) {
            parts.append(String(localized: "Archived"))
        }
        return parts.joined(separator: ", ")
    }

    /// Compact iTunes season/episode (`S2 E5`) when feed provides numbers; nil when unknown.
    private var seasonEpisodeCaptionText: String? {
        episode.seasonEpisodeCaption
    }

    /// Publish-date caption: Today / Yesterday / N days ago (≤7) / medium absolute.
    private var formattedPubDateCaption: String? {
        guard let ms = episode.pubDateEpochMs else { return nil }
        let date = Date(timeIntervalSince1970: Double(ms) / 1000)
        return EpisodeDateFormatting.listCaption(for: date)
    }

    /// Prefer feed `itunes:duration` / media duration; fall back to saved playback duration.
    /// Hidden when both unknown or zero — never invents a length.
    private var knownDurationSeconds: Double? {
        if episode.hasKnownDuration {
            return episode.durationSeconds
        }
        let played = state.durationSeconds
        if played.isFinite, played > 0 {
            return played
        }
        return nil
    }

    /// `m:ss` / `h:mm:ss` via the same formatter as the full-player scrubber / share timestamp.
    private var formattedKnownDuration: String? {
        PodcastEpisode.formatPlaybackPosition(knownDurationSeconds)
    }

    /// Prefer on-disk file size when an offline copy exists; else feed enclosure `PodcastEpisode.size` when > 0.
    /// Same honesty as Downloads rows (`DownloadedEpisode.knownByteSize`). Hidden when unknown — never invents MB.
    private var knownByteSize: Int64? {
        if let item = downloads.downloads.first(where: { $0.id == episode.id }) {
            return item.knownByteSize()
        }
        // Local-folder `file://` (or other localURL) not necessarily in the downloads catalog.
        if let url = downloads.localURL(for: episode) {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile != false,
               let size = values?.fileSize,
               size > 0 {
                return Int64(size)
            }
        }
        if episode.size > 0 {
            return episode.size
        }
        return nil
    }

    /// Compact KB/MB/GB via `DownloadStorageUsage.formatBytes` / `ByteCountFormatter` when `knownByteSize` is set.
    private var formattedKnownByteSize: String? {
        guard let bytes = knownByteSize else { return nil }
        return DownloadStorageUsage.formatBytes(bytes)
    }
}

/// Feed-detail / description block for channel `podcast:updateFrequency` (display-only).
struct FeedUpdateFrequencyDetailBlock: View {
    let frequency: PodcastUpdateFrequency

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label = frequency.displayLabel {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.2), in: Capsule())
            } else {
                Text(String(localized: "Update frequency"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if frequency.isComplete {
                Text(String(localized: "This podcast claims it will not release further episodes. This does not change Keep updated or refresh."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let rrule = frequency.displayRrule {
                Text(String(localized: "Recurrence \(rrule)"))
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let dtstart = frequency.displayDtstart {
                Text(String(localized: "Starts \(dtstart)"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(frequency.accessibilityLabel)
    }
}

/// Compact capsule for Subscriptions / preview when `podcast:updateFrequency` is present.
struct FeedUpdateFrequencyCapsule: View {
    let frequency: PodcastUpdateFrequency
    var compact: Bool = false

    var body: some View {
        if let label = frequency.displayLabel {
            Text(label)
                .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                .padding(.horizontal, compact ? 6 : 8)
                .padding(.vertical, compact ? 2 : 4)
                .background(Color.secondary.opacity(0.2), in: Capsule())
                .accessibilityLabel(frequency.accessibilityLabel)
        } else if frequency.hasContent {
            Text(String(localized: "Update frequency"))
                .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                .padding(.horizontal, compact ? 6 : 8)
                .padding(.vertical, compact ? 2 : 4)
                .background(Color.secondary.opacity(0.2), in: Capsule())
                .accessibilityLabel(frequency.accessibilityLabel)
        }
    }
}
