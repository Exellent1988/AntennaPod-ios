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
    @State private var showArchiveAllConfirm = false
    @State private var showEnqueueAllConfirm = false
    @State private var showEnqueueAllUnplayedConfirm = false
    @State private var showDeleteDownloadsConfirm = false
    @State private var showUnsubscribeConfirm = false
    /// Episode pending swipe Remove-from-queue confirmation (nil = dismissed).
    @State private var episodePendingRemoveFromQueue: PodcastEpisode?
    @State private var showFeedURLCopied = false
    @State private var showFundingURLCopied = false
    @State private var showFundingLabelCopied = false
    @State private var showPodcastWebsiteURLCopied = false
    @State private var showPodcastGuidCopied = false
    @State private var showPodcastTitleCopied = false
    @State private var showDiscussURLCopied = false
    @State private var showDiscussProtocolCopied = false
    @State private var showDiscussAccountCopied = false
    @State private var showTrailerURLCopied = false
    @State private var showTrailerTitleCopied = false
    @State private var showTrailerPubDateCopied = false
    @State private var showTrailerSeasonCopied = false
    @State private var showTrailerTypeCopied = false
    @State private var showTrailerLengthCopied = false
    @State private var showLockedOwnerCopied = false
    @State private var showAuthorCopied = false
    @State private var showLanguageCopied = false
    @State private var showCategoriesCopied = false
    @State private var showMediumCopied = false
    @State private var showItunesTypeCopied = false
    @State private var showUpdateFrequencyCopied = false
    @State private var showUpdateFrequencyRruleCopied = false
    @State private var showUpdateFrequencyDtstartCopied = false
    @State private var showItunesCompleteCopied = false
    @State private var showExplicitCopied = false
    @State private var showBlockedCopied = false
    @State private var showLastRefreshedCopied = false
    @State private var showFeedDescription = false
    @State private var isRescanningLocalFolder = false
    /// Error from this page's own Rescan folder. `store.lastError` also carries other feeds'
    /// Refresh all failures, which must not appear under this folder.
    @State private var localFolderRescanError: String?
    @Environment(\.dismiss) private var dismiss
    @State private var copyFeedURLFeedbackTick = 0
    @State private var copyFundingURLFeedbackTick = 0
    @State private var copyFundingLabelFeedbackTick = 0
    @State private var copyPodcastWebsiteURLFeedbackTick = 0
    @State private var copyPodcastGuidFeedbackTick = 0
    @State private var copyPodcastTitleFeedbackTick = 0
    @State private var copyDiscussURLFeedbackTick = 0
    @State private var copyDiscussProtocolFeedbackTick = 0
    @State private var copyDiscussAccountFeedbackTick = 0
    @State private var copyTrailerURLFeedbackTick = 0
    @State private var copyTrailerTitleFeedbackTick = 0
    @State private var copyTrailerPubDateFeedbackTick = 0
    @State private var copyTrailerSeasonFeedbackTick = 0
    @State private var copyTrailerTypeFeedbackTick = 0
    @State private var copyTrailerLengthFeedbackTick = 0
    @State private var copyLockedOwnerFeedbackTick = 0
    @State private var copyAuthorFeedbackTick = 0
    @State private var copyLanguageFeedbackTick = 0
    @State private var copyCategoriesFeedbackTick = 0
    @State private var copyMediumFeedbackTick = 0
    @State private var copyItunesTypeFeedbackTick = 0
    @State private var copyUpdateFrequencyFeedbackTick = 0
    @State private var copyUpdateFrequencyRruleFeedbackTick = 0
    @State private var copyUpdateFrequencyDtstartFeedbackTick = 0
    @State private var copyItunesCompleteFeedbackTick = 0
    @State private var copyExplicitFeedbackTick = 0
    @State private var copyBlockedFeedbackTick = 0
    @State private var copyLastRefreshedFeedbackTick = 0
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

    /// Stable absolute text for copy/share; the visible relative caption is intentionally not copied alone.
    private var lastRefreshedShareText: String? {
        guard let lastRefreshedAt else { return nil }
        let absolute = lastRefreshedAt.formatted(date: .abbreviated, time: .shortened)
        return String(localized: "Last refreshed \(absolute)")
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

    /// Same feed-provided category list used by Copy, Share, and the combined VoiceOver label.
    private var displayCategoriesShareText: String {
        displayCategories.joined(separator: " · ")
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

    /// Channel podcast:txt when the feed provided them — empty → hide (display-only Copy / Share / Open; no special clients).
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

    /// VoiceOver for the podcast:locked=yes badge and honest footnote.
    /// The optional owner has its own label and actions so it stays distinct from the claim.
    private var feedLockedAccessibilityLabel: String {
        [
            String(localized: "Locked"),
            String(localized: "This feed claims to be locked for transfer. This app does not verify ownership.")
        ].joined(separator: ". ")
    }

    /// VoiceOver for podcast:block / itunes:block yes badge + honest directory display-only footnote.
    private var feedBlockedAccessibilityLabel: String {
        liveFeed.podcastBlockAccessibilityLabel
    }

    /// Channel podcast:updateFrequency when present — hide when absent (never invent; display-only).
    private var displayUpdateFrequency: PodcastUpdateFrequency? {
        liveFeed.displayUpdateFrequency
    }

    private var displayItunesCompleteShareText: String {
        liveFeed.itunesCompleteShareText
    }

    private var displayExplicitShareText: String {
        String(localized: "Explicit")
    }

    private var displayBlockedShareText: String {
        feedBlockedAccessibilityLabel
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
    /// Use `liveFeed`, not the navigation snapshot: a refresh while this page stays open
    /// updates the episode rows, and the Full / Trailer / Bonus / Other chips must follow.
    private var feedEpisodeTypeFilterChips: [EpisodeTypeFilter] {
        EpisodeTypeFilter.chips(presentIn: liveFeed.episodes, selected: settings.feedEpisodeTypeFilter)
    }

    private var showFeedEpisodeTypeFilterChips: Bool {
        EpisodeTypeFilter.shouldShowChipRow(presentIn: liveFeed.episodes, selected: settings.feedEpisodeTypeFilter)
    }

    private var isFiltering: Bool {
        settings.feedEpisodeFilter != .all
            || settings.feedEpisodeTypeFilter != .all
            || !debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Status or type chip only. Search is not a chip: a search miss with both chips on All
    /// must say search, not filter (`isFiltering` includes the query).
    private var hasFeedChipFilter: Bool {
        settings.feedEpisodeFilter != .all || settings.feedEpisodeTypeFilter != .all
    }

    /// AntennaPod-like info bar: episode count + remaining over the **visible** Feed detail list
    /// (sort → status → type → searchable). Remaining per episode = `max(0, duration − position)` when
    /// duration known; unplayed with duration contributes full duration; **played** (not current)
    /// → 0; **unknown duration skipped** (tilde when any skipped). Currently playing uses live
    /// `PlaybackService` position/duration. Wall-clock by default; optional Settings → Remaining time respects speed divides by feed/default speed (estimate).
    /// Distinct from **Download all unplayed** / **Mark all as played** / **Mark all as unplayed** / **Add all unplayed to queue** / **Add all to queue** / **Delete downloads** / **Play random** full-feed eligibility counts.
    private func feedRemainingInfoLabel(
        visibleEpisodes: [PodcastEpisode],
        summary: EpisodeRemainingTime.Summary
    ) -> String? {
        guard !visibleEpisodes.isEmpty else { return nil }
        return EpisodeRemainingTime.episodesInfoBarLabel(for: summary)
    }

    private var feedEpisodesEmptyStateAccessibilityValue: String {
        if liveFeed.episodes.isEmpty {
            if LocalFolderFeed.isLocalFolderFeed(liveFeed) {
                return String(localized: "This folder has no \(LocalFolderFeed.audioFormatsDisplay) files yet. Add files in Files, then rescan the folder or refresh Subscriptions.")
            }
            return String(localized: "This podcast has no episodes yet. Pull to refresh on Subscriptions.")
        }
        if hasFeedChipFilter {
            return String(localized: "No episodes match the selected status or episode type filters. Episodes remain in this podcast’s full catalog. Download all unplayed, Mark all, Add all to queue, and Play random still use the full feed, not this empty view.")
        }
        return String(localized: "No episodes match your search. Episodes remain in this podcast’s full catalog. Download all unplayed, Mark all, Add all to queue, and Play random still use the full feed, not this empty view.")
    }

    /// VoiceOver recovery hint for the filter/search mismatch empty state only.
    private var feedNoMatchAccessibilityHint: String {
        if hasFeedChipFilter {
            return String(localized: "Change or clear the status or episode type filter to see other episodes in this podcast. This does not delete or unsubscribe.")
        }
        return String(localized: "Change or clear search to see other episodes in this podcast. This does not delete or unsubscribe.")
    }

    private func feedRemainingAccessibilityLabel(
        visibleEpisodes: [PodcastEpisode],
        summary: EpisodeRemainingTime.Summary
    ) -> String {
        guard let label = feedRemainingInfoLabel(visibleEpisodes: visibleEpisodes, summary: summary) else { return "" }
        var parts = [String(localized: "Feed remaining time \(label)")]
        let unknown = summary.unknownCount
        if unknown > 0 {
            parts.append(String(localized: "Remaining time excludes \(unknown) episode(s) with unknown duration"))
        }
        return parts.joined(separator: ". ")
    }

    /// VoiceOver hint for the Feed remaining bar. The visible label stays the
    /// count and time. This says whether that time is wall-clock or divided by
    /// podcast/default speed, and that the bar is this feed's sort, status,
    /// episode-type, and search list. Distinct from Download all unplayed /
    /// Mark all as played / Mark all as unplayed / Archive all /
    /// Add all unplayed to queue / Add all to queue / Delete downloads /
    /// Play random (full feed) and from other remaining bars.
    private var feedRemainingAccessibilityHint: String {
        if settings.remainingTimeRespectsSpeed {
            return String(localized: "Estimate. Remaining time respects speed is on, so each episode is divided by that podcast’s playback speed, or Default speed, never below 0.5. This is not the live session rate and not Volume boost. The Feed bar is this feed’s visible episode list after sort, the status chip (All, Unplayed, or Played), the episode type (All, Full, Trailer, Bonus, or Other), and search. Sort changes order only. Unplayed means not played and not archived. Played episodes that are not currently playing count as zero. It is not the full feed catalog behind Download all unplayed, Mark all as played, Mark all as unplayed, Archive all, Add all unplayed to queue, Add all to queue, Delete downloads, or Play random. Unknown durations are left out and no time is invented. The episode that is playing uses the live position, but the divisor stays the podcast or default speed. This is not the Archived remaining bar, the Downloads remaining bar, the History remaining bar, the Favorites remaining bar, the All Episodes remaining bar, the Queue remaining bar, the Inbox remaining bar, the Subscriptions unplayed remaining bar, a Home preview remaining bar, the mini player, or Lock Screen. It does not play, download, or mark episodes played.")
        }
        return String(localized: "Wall-clock remaining. Remaining time respects speed is off, so playback speed does not change this total. The Feed bar is this feed’s visible episode list after sort, the status chip (All, Unplayed, or Played), the episode type (All, Full, Trailer, Bonus, or Other), and search. Sort changes order only. Unplayed means not played and not archived. Played episodes that are not currently playing count as zero. It is not the full feed catalog behind Download all unplayed, Mark all as played, Mark all as unplayed, Archive all, Add all unplayed to queue, Add all to queue, Delete downloads, or Play random. Unknown durations are left out and no time is invented. The episode that is playing uses the live position. This is not the Archived remaining bar, the Downloads remaining bar, the History remaining bar, the Favorites remaining bar, the All Episodes remaining bar, the Queue remaining bar, the Inbox remaining bar, the Subscriptions unplayed remaining bar, a Home preview remaining bar, the mini player, or Lock Screen. It does not play, download, or mark episodes played.")
    }

    private func feedRemainingSummary(for visibleEpisodes: [PodcastEpisode]) -> EpisodeRemainingTime.Summary {
        EpisodeRemainingTime.summarize(
            episodes: visibleEpisodes,
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

    /// Uncapped eligibility count — soft-cap confirm honesty when truncated.
    private var downloadAllEligibleTotalCount: Int {
        downloads.eligibleForFeedDownloadAllCount(in: liveFeed, store: store)
    }

    private var downloadAllConfirmMessage: String {
        let capped = downloadAllCandidates.count
        let total = downloadAllEligibleTotalCount
        let softCap = settings.feedDownloadUnplayedSoftCap.episodeCap
        let head: String
        if total > capped {
            head = String(
                localized: "Queues download of \(capped) of \(total) eligible unplayed episodes (newest first, soft cap \(softCap))."
            )
        } else {
            head = String(
                localized: "Queues download of \(capped) unplayed episodes (newest first, soft cap \(softCap))."
            )
        }
        return head + " " + String(
            localized: "Played, archived, already downloaded, and local-folder files are skipped. Requires http(s) enclosure. Uses the full feed catalog — not the chip or search filter. Manual download Wi‑Fi only, parallel-download cap, and storage limit still apply."
        )
    }

    private var downloadAllAccessibilityHint: String {
        let capped = downloadAllCandidates.count
        let total = downloadAllEligibleTotalCount
        let softCap = settings.feedDownloadUnplayedSoftCap.episodeCap
        let tail = String(
            localized: "Asks for confirmation. Uses the full feed catalog — not the chip or search filter. Requires http(s) enclosure. Manual download Wi‑Fi only, parallel-download cap, and storage limit still apply."
        )
        if total > capped {
            return String(
                localized: "Queues the \(capped) newest eligible unplayed downloads (soft cap \(softCap); \(total) match on this podcast). Skips played, archived, already downloaded, and local-folder files."
            ) + " " + tail
        }
        return String(
            localized: "Queues downloads for unplayed episodes in this podcast that are not archived and not already downloaded (soft cap \(softCap))."
        ) + " " + tail
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

    private var archiveAllFeedCandidatesCount: Int {
        store.archiveAllCandidateCount(inFeedId: liveFeed.id)
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

                    if let err = localFolderRescanError, LocalFolderFeed.isLocalFolderFeed(liveFeed) {
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text(author)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel(String(localized: "Author \(author)"))

                        HStack(spacing: 12) {
                            Button {
                                copyAuthor(author)
                            } label: {
                                Label("Copy author", systemImage: "doc.on.doc")
                                    .font(.subheadline)
                            }
                            .accessibilityLabel(String(localized: "Copy author"))
                            .accessibilityHint(
                                String(localized: "Copies the feed-provided author string to the pasteboard; display-only; no profile URL")
                            )

                            ShareLink(
                                item: author,
                                subject: Text(feedDisplayTitle)
                            ) {
                                Label("Share author", systemImage: "square.and.arrow.up")
                                    .font(.subheadline)
                            }
                            .accessibilityLabel(String(localized: "Share author"))
                            .accessibilityHint(
                                String(localized: "Shares the same feed-provided author string as plain text; no profile URL")
                            )
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Feed language when present (itunes:language / RSS language / xml:lang); hide when missing.
            if let language = displayLanguage {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(language)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel(String(localized: "Language \(language)"))

                        HStack(spacing: 12) {
                            Button {
                                copyLanguage(language)
                            } label: {
                                Label("Copy language", systemImage: "doc.on.doc")
                                    .font(.subheadline)
                            }
                            .accessibilityLabel(String(localized: "Copy language"))
                            .accessibilityHint(
                                String(localized: "Copies the same feed-provided language string shown above to the pasteboard; display-only; no code invented")
                            )

                            ShareLink(
                                item: language,
                                subject: Text(feedDisplayTitle)
                            ) {
                                Label("Share language", systemImage: "square.and.arrow.up")
                                    .font(.subheadline)
                            }
                            .accessibilityLabel(String(localized: "Share language"))
                            .accessibilityHint(
                                String(localized: "Shares the same feed-provided language string shown above as plain text; display-only; no code invented")
                            )
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Last successful network refresh — hide when nil / local-folder (Rescan is not a network refresh).
            if let lastRefreshedAt, let lastRefreshedShareText {
                Section {
                    LabeledContent(String(localized: "Last refreshed")) {
                        Text(lastRefreshedAt, style: .relative)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(lastRefreshedShareText)

                    HStack(spacing: 12) {
                        Button {
                            copyLastRefreshed(lastRefreshedShareText)
                        } label: {
                            Label("Copy last refreshed timestamp", systemImage: "doc.on.doc")
                                .font(.subheadline)
                        }
                        .accessibilityLabel(String(localized: "Copy last refreshed timestamp"))
                        .accessibilityHint(
                            String(localized: "Copies the stable absolute Last refreshed timestamp shown above to the pasteboard; does not refresh the feed")
                        )

                        ShareLink(item: lastRefreshedShareText, subject: Text(feedDisplayTitle)) {
                            Label("Share last refreshed timestamp", systemImage: "square.and.arrow.up")
                                .font(.subheadline)
                        }
                        .accessibilityLabel(String(localized: "Share last refreshed timestamp"))
                        .accessibilityHint(
                            String(localized: "Shares the same stable absolute Last refreshed timestamp shown above as plain text; does not refresh the feed")
                        )
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Channel podcast:medium when present — raw feed string; hide when missing (never invent/remap; display-only).
            if let medium = displayMedium {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(medium)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.2), in: Capsule())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel(String(localized: "Medium \(medium)"))
                        mediumActions(medium)
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Channel itunes:type when present — Episodic/Serial (localized) or raw; hide when missing (never invent).
            // Capsule is display-only; Serial may one-shot set per-feed Oldest first when episodeSort is still nil.
            if let itunesType = displayItunesType {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(itunesType)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.2), in: Capsule())
                            .accessibilityLabel(liveFeed.itunesTypeAccessibilityLabel ?? itunesType)
                        itunesTypeActions(itunesType)
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
                    VStack(alignment: .leading, spacing: 8) {
                        FeedUpdateFrequencyDetailBlock(frequency: uf)
                        updateFrequencyActions(uf)
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Channel itunes:complete yes/true only — display-only Apple claim; distinct from podcast:updateFrequency complete; no Keep updated/refresh change.
            if liveFeed.isItunesComplete {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
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
                        itunesCompleteActions
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Channel itunes:explicit only — hide when feed does not mark explicit (never invent).
            if liveFeed.isExplicit {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "Explicit"))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.2), in: Capsule())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel(String(localized: "Explicit"))
                        explicitActions
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Channel podcast:locked=yes only — display-only claim; no owner verification / host block.
            if liveFeed.isLocked {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(localized: "Locked"))
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.2), in: Capsule())
                            Text(String(localized: "This feed claims to be locked for transfer. This app does not verify ownership."))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(feedLockedAccessibilityLabel)

                        if let owner = liveFeed.displayLockedOwner {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(String(localized: "Locked owner \(owner)"))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .accessibilityLabel(String(localized: "Locked owner \(owner)"))
                                HStack(spacing: 12) {
                                    Button {
                                        copyLockedOwner(owner)
                                    } label: {
                                        Label("Copy locked owner", systemImage: "doc.on.doc")
                                            .font(.subheadline)
                                    }
                                    .accessibilityLabel(String(localized: "Copy locked owner"))
                                    .accessibilityHint(String(localized: "Copies the feed-provided locked owner string to the pasteboard; display-only; no ownership verification"))

                                    if let url = lockedOwnerShareURL(owner) {
                                        ShareLink(
                                            item: url,
                                            subject: Text(feedDisplayTitle)
                                        ) {
                                            Label("Share locked owner", systemImage: "square.and.arrow.up")
                                                .font(.subheadline)
                                        }
                                        .accessibilityLabel(String(localized: "Share locked owner"))
                                        .accessibilityHint(String(localized: "Shares the feed-provided locked owner string; display-only; no ownership verification"))
                                    } else {
                                        ShareLink(
                                            item: owner,
                                            subject: Text(feedDisplayTitle)
                                        ) {
                                            Label("Share locked owner", systemImage: "square.and.arrow.up")
                                                .font(.subheadline)
                                        }
                                        .accessibilityLabel(String(localized: "Share locked owner"))
                                        .accessibilityHint(String(localized: "Shares the feed-provided locked owner string; display-only; no ownership verification"))
                                    }
                                }
                            }
                            .accessibilityElement(children: .contain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Channel podcast:block / itunes:block yes/true — display-only directory metadata; distinct from podcast:locked; no subscribe/play block.
            if liveFeed.isBlocked {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
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
                        blockedActions
                    }
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
                            .accessibilityHint(String(localized: "Copies the feed-provided podcast GUID to the pasteboard as plain text. No confirmation. Distinct from the podcast, feed URL, website, funding, and discussion copies, and from Share podcast GUID. Does not open a link, change subscriptions, or invent a GUID when missing."))

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
                    VStack(alignment: .leading, spacing: 8) {
                        FeedCategoryChips(categories: displayCategories)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(
                                String(localized: "Categories \(displayCategoriesShareText)")
                            )

                        HStack(spacing: 12) {
                            Button {
                                copyCategories()
                            } label: {
                                Label("Copy categories", systemImage: "doc.on.doc")
                                    .font(.subheadline)
                            }
                            .accessibilityLabel(String(localized: "Copy categories"))
                            .accessibilityHint(
                                String(localized: "Copies the same feed-provided category list shown above to the pasteboard; display-only; no App Store taxonomy invented")
                            )

                            ShareLink(
                                item: displayCategoriesShareText,
                                subject: Text(feedDisplayTitle)
                            ) {
                                Label("Share categories", systemImage: "square.and.arrow.up")
                                    .font(.subheadline)
                            }
                            .accessibilityLabel(String(localized: "Share categories"))
                            .accessibilityHint(
                                String(localized: "Shares the same feed-provided category list shown above as plain text; display-only; no App Store taxonomy invented")
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .contain)
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
            // Channel podcast:socialInteract — Discuss opens http(s) uri; Copy / Share exact protocol, account ID, and URL.
            // Feed-provided only — never invent URLs, protocol values, or account IDs; no in-app Fediverse client / posting.
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
            // Channel podcast:txt — purpose (raw feed string) + text; Copy / Share / Open http(s); hide when none.
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

            // Sort + filter + search the whole feed once per body (the body reruns on each 0.5s
            // playback tick); the info bar, its VoiceOver label, and the list share this result.
            let visibleEpisodes = filteredEpisodes
            let remainingSummary = feedRemainingSummary(for: visibleEpisodes)
            // AntennaPod-like Feed detail info bar (visible sort→status→type→search list remaining time).
            // Distinct from Download all unplayed / Mark all as played / Mark all as unplayed / Add all unplayed to queue / Add all to queue / Delete downloads / Play random full-feed eligibility counts.
            if let remainingLabel = feedRemainingInfoLabel(visibleEpisodes: visibleEpisodes, summary: remainingSummary) {
                Section {
                    Text(remainingLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(feedRemainingAccessibilityLabel(visibleEpisodes: visibleEpisodes, summary: remainingSummary))
                        .accessibilityHint(feedRemainingAccessibilityHint)
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
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(String(localized: "No audio files"))
                        .accessibilityValue(feedEpisodesEmptyStateAccessibilityValue)
                    } else {
                        ContentUnavailableView(
                            "No episodes",
                            systemImage: "list.bullet",
                            description: Text("This podcast has no episodes yet. Pull to refresh on Subscriptions.")
                        )
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(String(localized: "No episodes"))
                        .accessibilityValue(feedEpisodesEmptyStateAccessibilityValue)
                    }
                } else if visibleEpisodes.isEmpty {
                    ContentUnavailableView(
                        "No matching episodes",
                        systemImage: "magnifyingglass",
                        description: Text(
                            hasFeedChipFilter
                                ? String(localized: "No episodes match your filter.")
                                : String(localized: "No episodes match your search.")
                        )
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(String(localized: "No matching episodes"))
                    .accessibilityValue(feedEpisodesEmptyStateAccessibilityValue)
                    .accessibilityHint(feedNoMatchAccessibilityHint)
                } else {
                    ForEach(visibleEpisodes) { episode in
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
                                        ? String(localized: "Marks this episode as unplayed. No confirmation. Does not delete downloads, remove from queue, or stop playback.")
                                        : String(localized: "Marks this episode as played. No confirmation. Removes it from the queue. May reset playback position and auto-delete the download when those settings are enabled.")
                                )
                                Button {
                                    store.toggleArchived(episode.id)
                                } label: {
                                    Label(
                                        store.isArchived(episode.id) ? String(localized: "Restore") : String(localized: "Archive"),
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
                                .accessibilityHint(
                                    String(localized: "Places this episode immediately after the currently playing queue item, or at the head if nothing is playing or current is not queued. Moves it if already queued — no duplicate. No confirmation. Queue lock does not block Play Next. Does not start playback, download, or mark played.")
                                )
                                if store.isInQueue(episode.id) {
                                    Button(role: .destructive) {
                                        episodePendingRemoveFromQueue = episode
                                    } label: {
                                        Label("Remove from queue", systemImage: "minus.circle")
                                    }
                                    .accessibilityHint(
                                        String(localized: "Asks for confirmation, then removes this episode from the queue only. Does not delete the download, mark played, or stop playback.")
                                    )
                                } else {
                                    Button {
                                        store.enqueue(episode)
                                    } label: {
                                        Label("Queue", systemImage: "text.append")
                                    }
                                    .tint(.purple)
                                }
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
                .accessibilityHint(String(localized: "Orders this podcast’s episode list only: Newest first, Oldest first, Shortest first, Longest first, Title A–Z, or Title Z–A. Saved per podcast — same override as Podcast settings → Episode sort. Serial may auto-set Oldest first once when unset; itunes:type capsule stays display-only. Does not rewrite the global Feed episode sort alone. Changing this does not reorder other podcasts or start a refresh."))
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
                            .accessibilityHint(String(localized: "Opens the feed-provided podcast website http(s) link in the system browser — not an in-app WebView. No confirmation. Never uses the feed RSS URL or an episode webpage. Distinct from Open episode website, Copy podcast website, and Share podcast website. Does not subscribe, download, or change playback."))

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

                            if let label = liveFeed.displayFundingLabel {
                                Button {
                                    copyFundingLabel(label)
                                } label: {
                                    Label("Copy funding label", systemImage: "doc.on.doc")
                                }
                                .accessibilityLabel(String(localized: "Copy funding label"))
                                .accessibilityHint(
                                    String(localized: "Copies the exact feed-provided funding label shown in the Support action to the pasteboard; does not process payments")
                                )

                                ShareLink(
                                    item: label,
                                    subject: Text(feedDisplayTitle)
                                ) {
                                    Label("Share funding label", systemImage: "square.and.arrow.up")
                                }
                                .accessibilityLabel(String(localized: "Share funding label"))
                                .accessibilityHint(
                                    String(localized: "Shares the exact feed-provided funding label shown in the Support action as plain text; does not process payments")
                                )
                            }
                        }

                        if let interact = liveFeed.preferredSocialInteract,
                           let url = interact.discussionURL {
                            if let accountId = interact.displayAccountId {
                                Button {
                                    copyDiscussAccountId(accountId)
                                } label: {
                                    Label("Copy discuss account ID", systemImage: "doc.on.doc")
                                }
                                .accessibilityLabel(String(localized: "Copy discuss account ID"))
                                .accessibilityHint(
                                    String(localized: "Copies the displayed feed-provided discussion account ID as plain text; does not post as you")
                                )

                                ShareLink(
                                    item: accountId,
                                    subject: Text(feedDisplayTitle),
                                    message: Text("\(feedDisplayTitle) — \(String(localized: "Discuss account ID"))")
                                ) {
                                    Label("Share discuss account ID", systemImage: "square.and.arrow.up")
                                }
                                .accessibilityLabel(String(localized: "Share discuss account ID"))
                                .accessibilityHint(
                                    String(localized: "Shares the displayed feed-provided discussion account ID as plain text; does not post as you")
                                )
                            }

                            if let protocolText = interact.displayProtocol {
                                Button {
                                    copyDiscussProtocol(protocolText)
                                } label: {
                                    Label("Copy discuss protocol", systemImage: "doc.on.doc")
                                }
                                .accessibilityLabel(String(localized: "Copy discuss protocol"))
                                .accessibilityHint(
                                    String(localized: "Copies the displayed feed-provided discussion protocol to the pasteboard; does not post as you")
                                )

                                ShareLink(item: protocolText) {
                                    Label("Share discuss protocol", systemImage: "square.and.arrow.up")
                                }
                                .accessibilityLabel(String(localized: "Share discuss protocol"))
                                .accessibilityHint(
                                    String(localized: "Shares the displayed feed-provided discussion protocol as plain text; does not post as you")
                                )
                            }

                            Button {
                                openURL(url)
                            } label: {
                                Label("Discuss", systemImage: "bubble.left.and.bubble.right")
                            }
                            .accessibilityLabel(String(localized: "Discuss"))
                            .accessibilityHint(String(localized: "Opens the feed-provided discussion http(s) link in the system browser — not an in-app WebView. No confirmation. Does not post as you. Never uses the feed RSS URL or the podcast website. Distinct from Copy discuss URL, Share discuss URL, and Open podcast website. Does not subscribe, download, or change playback."))

                            Button {
                                copyDiscussURL(url)
                            } label: {
                                Label("Copy discuss URL", systemImage: "doc.on.doc")
                            }
                            .accessibilityLabel(String(localized: "Copy discuss URL"))
                            .accessibilityHint(
                                String(localized: "Copies the feed-provided discussion URL to the pasteboard. No confirmation. Does not post as you. Never uses the feed RSS URL or the podcast website. Distinct from Discuss, Share discuss URL, and Copy feed URL. Does not open a browser, subscribe, or download.")
                            )

                            ShareLink(
                                item: url,
                                subject: Text(feedDisplayTitle),
                                message: Text("\(feedDisplayTitle) — \(String(localized: "Discuss"))")
                            ) {
                                Label("Share discuss URL", systemImage: "square.and.arrow.up")
                            }
                            .accessibilityLabel(String(localized: "Share discuss URL"))
                            .accessibilityHint(
                                String(localized: "Opens the system share sheet with the feed-provided discussion URL. Does not post as you. Never uses the feed RSS URL or the podcast website. Distinct from Discuss, Copy discuss URL, and Share feed URL. Sharing is your choice and does not subscribe or download.")
                            )
                        }

                        if let title = EpisodeCopyLinks.trimmedFeedTitle(feedDisplayTitle) {
                            Button {
                                copyPodcastTitle(title)
                            } label: {
                                Label("Copy podcast title", systemImage: "doc.on.doc")
                            }
                            .accessibilityLabel(String(localized: "Copy podcast title"))
                            .accessibilityHint(String(localized: "Copies the trimmed podcast display title to the pasteboard; hidden when the title is empty; no title invented"))

                            ShareLink(item: title, subject: Text(title)) {
                                Label("Share podcast title", systemImage: "square.and.arrow.up")
                            }
                            .accessibilityLabel(String(localized: "Share podcast title"))
                            .accessibilityHint(String(localized: "Shares the trimmed podcast display title as plain text; hidden when the title is empty; no title invented"))
                        }

                        Button {
                            copyFeedURL()
                        } label: {
                            Label("Copy feed URL", systemImage: "doc.on.doc")
                        }
                        .disabled(!canCopyFeedURL)
                        .accessibilityLabel(String(localized: "Copy feed URL"))
                        .accessibilityHint(String(localized: "Copies the feed RSS or Atom URL to the pasteboard. No confirmation. Disabled for local-folder podcasts and empty URLs. Distinct from the podcast website, funding, and discussion links, and from Share feed URL. Does not subscribe, refresh, or open a browser."))

                        if let url = feedURLShareURL {
                            ShareLink(
                                item: url,
                                subject: Text("\(feedDisplayTitle) — \(String(localized: "Feed URL"))"),
                                message: Text("\(feedDisplayTitle) — \(String(localized: "Feed URL"))")
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
                                subject: Text("\(feedDisplayTitle) — \(String(localized: "Feed URL"))"),
                                message: Text("\(feedDisplayTitle) — \(String(localized: "Feed URL"))")
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
                            .accessibilityHint(String(localized: "Copies the feed-provided podcast GUID to the pasteboard as plain text. No confirmation. Distinct from the podcast, feed URL, website, funding, and discussion copies, and from Share podcast GUID. Does not open a link, change subscriptions, or invent a GUID when missing."))

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
                        .accessibilityHint(String(localized: "Plays a random non-archived episode from this podcast’s full catalog with playable media. Prefers unplayed when any remain. Ignores status, episode type, and search filters. Does not reorder the feed list. No confirmation."))

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
                        .accessibilityHint(String(localized: "Pins or unpins this podcast above unpinned ones on Subscriptions for every sort (Recently updated, Alphabetical, and others). Not a separate sort mode. Local preference only — not synced to gpodder. Included in iOS JSON backup with other feed settings. Cleared when you unsubscribe. Does not unsubscribe, change tags, or change the Subscriptions sort preference. Toggles immediately. No confirmation."))

                        Button {
                            showDownloadAllConfirm = true
                        } label: {
                            Label("Download all unplayed", systemImage: "arrow.down.circle")
                        }
                        .disabled(downloadAllCandidates.isEmpty)
                        .accessibilityLabel(String(localized: "Download all unplayed"))
                        .accessibilityHint(downloadAllAccessibilityHint)

                        Button {
                            showMarkAllPlayedConfirm = true
                        } label: {
                            Label("Mark all as played", systemImage: "checkmark.circle")
                        }
                        .disabled(markAllPlayedCandidates.isEmpty)
                        .accessibilityHint(String(localized: "Asks for confirmation, then marks unplayed, non-archived episodes in this podcast’s full feed catalog as played. Ignores status, episode type, search, and sort filters. Does not archive; Auto-delete after playing still applies when enabled."))

                        Button {
                            showMarkAllUnplayedConfirm = true
                        } label: {
                            Label("Mark all as unplayed", systemImage: "circle")
                        }
                        .disabled(markAllUnplayedCandidates.isEmpty)
                        .accessibilityHint(String(localized: "Asks for confirmation, then marks played episodes in this podcast’s full feed catalog as unplayed, including archived. Ignores status, episode type, search, and sort filters. Does not delete downloads, remove from queue, stop playback, or unarchive."))

                        Button {
                            showArchiveAllConfirm = true
                        } label: {
                            Label("Archive all", systemImage: "archivebox")
                        }
                        .disabled(archiveAllFeedCandidatesCount == 0)
                        .accessibilityLabel(String(localized: "Archive all"))
                        .accessibilityHint(String(localized: "Asks for confirmation, then archives non-archived episodes in this podcast’s full feed catalog. Ignores status, episode type, search, and sort filters. Archived does not mean played. Does not mark played, delete downloads, or clear the queue. Distinct from global Archive all actions."))

                        Button {
                            showEnqueueAllUnplayedConfirm = true
                        } label: {
                            Label("Add all unplayed to queue", systemImage: "text.badge.plus")
                        }
                        .disabled(enqueueAllUnplayedFromFeedCandidates.isEmpty)
                        .accessibilityLabel(String(localized: "Add all unplayed to queue"))
                        .accessibilityHint(String(localized: "Asks for confirmation, then appends unplayed, non-archived episodes from this podcast’s full feed catalog that are not already queued, in this podcast’s episode sort order. Ignores status, episode type, search, and sort filters. Queue lock does not block enqueue. Distinct from Add all to queue, which also includes played and archived."))

                        Button {
                            showEnqueueAllConfirm = true
                        } label: {
                            Label("Add all to queue", systemImage: "text.append")
                        }
                        .disabled(enqueueAllFromFeedCandidatesCount == 0)
                        .accessibilityHint(String(localized: "Asks for confirmation, then appends episodes from this podcast’s full feed catalog that are not already queued, newest publish date first, including played and archived. Ignores status, episode type, search, and sort filters. Queue lock does not block enqueue."))

                        Button(role: .destructive) {
                            showDeleteDownloadsConfirm = true
                        } label: {
                            Label("Delete downloads", systemImage: "externaldrive.badge.minus")
                        }
                        .disabled(deleteFeedDownloadsEligible.isEmpty)
                        .accessibilityHint(String(localized: "Asks for confirmation, then deletes this podcast’s offline files, skipping favorites. Local files only — keeps played status, queue, favorites, and archive. Distinct from Unsubscribe, Delete played downloads, and Delete all downloads."))

                        Button(role: .destructive) {
                            showUnsubscribeConfirm = true
                        } label: {
                            Label("Unsubscribe", systemImage: "trash")
                        }
                        .accessibilityHint(String(localized: "Asks for confirmation, then removes this podcast from Subscriptions, its feed settings and tags, queue items from this feed, and favorites, archive, playback history, bookmarks, and private notes for its episodes. When this feed has offline downloads, you can keep them or delete only this feed’s files including favorites. Does not clear other podcasts’ downloads."))
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
            Text(downloadAllConfirmMessage)
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
                "Marks \(markAllPlayedCandidates.count) unplayed, non-archived episodes in this podcast as played. Uses the full feed catalog — not the status, episode type, search, or sort filter. Does not archive; auto-delete after playing still applies when enabled."
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
                "Marks \(markAllUnplayedCandidates.count) played episodes in this podcast as unplayed (including archived). Uses the full feed catalog — not the status, episode type, search, or sort filter. Does not delete downloads, remove from queue, stop playback, or unarchive."
            )
        }
        .confirmationDialog(
            "Archive all?",
            isPresented: $showArchiveAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Archive all") {
                store.archiveAll(inFeedId: liveFeed.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Archives \(archiveAllFeedCandidatesCount) non-archived episodes in this podcast’s full feed catalog, not the status, episode type, search, or sort filter. Archived does not mean played. Does not mark played, delete downloads, or clear the queue. Distinct from global Archive all actions."
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
                    "Deletes \(deleteFeedDownloadsEligible.count) offline file(s) for this podcast (\(deleteFeedDownloadsSizeLabel)). Skips \(deleteFeedDownloadsSkippedFavoritesCount) favorited download(s). Local files only — keeps played status, queue, favorites, and archive. Distinct from Unsubscribe, Delete played downloads, and Delete all downloads."
                )
            } else {
                Text(
                    "Deletes \(deleteFeedDownloadsEligible.count) offline file(s) for this podcast (\(deleteFeedDownloadsSizeLabel)). Skips favorited downloads. Local files only — keeps played status, queue, favorites, and archive. Distinct from Unsubscribe, Delete played downloads, and Delete all downloads."
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
                    "Unsubscribe from \"\(feedDisplayTitle)\"? Removes this podcast from Subscriptions, its feed settings and tags, queue items from this feed, and favorites, archive, playback history, bookmarks, and private notes for its episodes. This feed has \(unsubscribeFeedDownloadsCount) offline download(s) (\(unsubscribeFeedDownloadsSizeLabel)). Unsubscribe keeps those files; Unsubscribe and delete downloads removes only this feed’s offline files (incl. favorited). Does not clear other podcasts’ downloads or Delete all downloads."
                )
            } else {
                Text(
                    "Unsubscribe from \"\(feedDisplayTitle)\"? Removes this podcast from Subscriptions, its feed settings and tags, queue items from this feed, and favorites, archive, playback history, bookmarks, and private notes for its episodes. Downloaded files are kept."
                )
            }
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
            isPresented: $showFundingLabelCopied
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "Funding label copied to the pasteboard."))
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
            isPresented: $showPodcastTitleCopied
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "Podcast title copied to the pasteboard."))
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showDiscussURLCopied
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "Discuss URL copied to the pasteboard."))
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showDiscussProtocolCopied
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "Discuss protocol copied to the pasteboard."))
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showDiscussAccountCopied
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "Discuss account ID copied to the pasteboard."))
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showTrailerURLCopied
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "Trailer URL copied to the pasteboard."))
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showTrailerTitleCopied
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "Trailer title copied to the pasteboard."))
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showTrailerPubDateCopied
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "Trailer publication date copied to the pasteboard."))
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showTrailerSeasonCopied
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "Trailer season copied to the pasteboard."))
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showTrailerTypeCopied
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "Trailer type copied to the pasteboard."))
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showTrailerLengthCopied
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "Trailer size copied to the pasteboard."))
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showLockedOwnerCopied
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "Locked owner copied to the pasteboard."))
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showAuthorCopied
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "Podcast author copied to the pasteboard."))
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showLanguageCopied
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "Podcast language copied to the pasteboard."))
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showCategoriesCopied
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "Podcast categories copied to the pasteboard."))
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showMediumCopied
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "Podcast medium copied to the pasteboard."))
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showItunesTypeCopied
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "Podcast type copied to the pasteboard."))
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showUpdateFrequencyCopied
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "Update frequency copied to the pasteboard."))
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showUpdateFrequencyRruleCopied
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "Recurrence copied to the pasteboard."))
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showUpdateFrequencyDtstartCopied
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "Start timestamp copied to the pasteboard."))
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showItunesCompleteCopied
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "Complete claim copied to the pasteboard."))
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showExplicitCopied
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "Explicit badge copied to the pasteboard."))
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showBlockedCopied
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "Blocked claim copied to the pasteboard."))
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showLastRefreshedCopied
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "Last refreshed timestamp copied to the pasteboard."))
        }
        .sensoryFeedback(.success, trigger: copyFeedURLFeedbackTick)
        .sensoryFeedback(.success, trigger: copyFundingURLFeedbackTick)
        .sensoryFeedback(.success, trigger: copyFundingLabelFeedbackTick)
        .sensoryFeedback(.success, trigger: copyPodcastWebsiteURLFeedbackTick)
        .sensoryFeedback(.success, trigger: copyPodcastGuidFeedbackTick)
        .sensoryFeedback(.success, trigger: copyPodcastTitleFeedbackTick)
        .sensoryFeedback(.success, trigger: copyDiscussURLFeedbackTick)
        .sensoryFeedback(.success, trigger: copyDiscussProtocolFeedbackTick)
        .sensoryFeedback(.success, trigger: copyDiscussAccountFeedbackTick)
        .sensoryFeedback(.success, trigger: copyTrailerURLFeedbackTick)
        .sensoryFeedback(.success, trigger: copyTrailerTitleFeedbackTick)
        .sensoryFeedback(.success, trigger: copyTrailerPubDateFeedbackTick)
        .sensoryFeedback(.success, trigger: copyTrailerSeasonFeedbackTick)
        .sensoryFeedback(.success, trigger: copyTrailerTypeFeedbackTick)
        .sensoryFeedback(.success, trigger: copyTrailerLengthFeedbackTick)
        .sensoryFeedback(.success, trigger: copyLockedOwnerFeedbackTick)
        .sensoryFeedback(.success, trigger: copyAuthorFeedbackTick)
        .sensoryFeedback(.success, trigger: copyLanguageFeedbackTick)
        .sensoryFeedback(.success, trigger: copyCategoriesFeedbackTick)
        .sensoryFeedback(.success, trigger: copyMediumFeedbackTick)
        .sensoryFeedback(.success, trigger: copyItunesTypeFeedbackTick)
        .sensoryFeedback(.success, trigger: copyUpdateFrequencyFeedbackTick)
        .sensoryFeedback(.success, trigger: copyUpdateFrequencyRruleFeedbackTick)
        .sensoryFeedback(.success, trigger: copyUpdateFrequencyDtstartFeedbackTick)
        .sensoryFeedback(.success, trigger: copyItunesCompleteFeedbackTick)
        .sensoryFeedback(.success, trigger: copyExplicitFeedbackTick)
        .sensoryFeedback(.success, trigger: copyBlockedFeedbackTick)
        .sensoryFeedback(.success, trigger: copyLastRefreshedFeedbackTick)
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
        localFolderRescanError = nil
        // The rescan's own error, not a Refresh all error in the shared store message.
        localFolderRescanError = await store.refresh(liveFeed)
    }

    /// Network RSS/Atom feeds only — local-folder feeds use a synthetic `local-folder://` id, not a pasteable feed URL.
    private var canCopyFeedURL: Bool {
        let trimmed = liveFeed.feedUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !LocalFolderFeed.isLocalFolderFeed(liveFeed)
    }

    /// Without `user:password@` (`FeedURLNormalization.strippingCredentials`).
    private var feedURLShareString: String {
        FeedURLNormalization.strippingCredentials(liveFeed.feedUrl)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
        UIPasteboard.general.string = feedURLShareString
        copyFeedURLFeedbackTick += 1
        showFeedURLCopied = true
    }

    private func copyFundingURL(_ url: URL) {
        UIPasteboard.general.string = url.absoluteString
        copyFundingURLFeedbackTick += 1
        showFundingURLCopied = true
    }

    private func copyFundingLabel(_ label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UIPasteboard.general.string = trimmed
        copyFundingLabelFeedbackTick += 1
        showFundingLabelCopied = true
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

    private func copyDiscussProtocol(_ protocolText: String) {
        let trimmed = protocolText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UIPasteboard.general.string = trimmed
        copyDiscussProtocolFeedbackTick += 1
        showDiscussProtocolCopied = true
    }

    private func copyDiscussAccountId(_ accountId: String) {
        let trimmed = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UIPasteboard.general.string = trimmed
        copyDiscussAccountFeedbackTick += 1
        showDiscussAccountCopied = true
    }

    private func copyTrailerURL(_ url: URL) {
        UIPasteboard.general.string = url.absoluteString
        copyTrailerURLFeedbackTick += 1
        showTrailerURLCopied = true
    }

    private func lockedOwnerShareURL(_ owner: String) -> URL? {
        guard let url = URL(string: owner) else { return nil }
        let scheme = url.scheme?.lowercased()
        guard scheme == "mailto" || scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    private func copyAuthor(_ author: String) {
        UIPasteboard.general.string = author
        copyAuthorFeedbackTick += 1
        showAuthorCopied = true
    }

    private func copyLanguage(_ language: String) {
        UIPasteboard.general.string = language
        copyLanguageFeedbackTick += 1
        showLanguageCopied = true
    }

    private func copyCategories() {
        guard !displayCategories.isEmpty else { return }
        UIPasteboard.general.string = displayCategoriesShareText
        copyCategoriesFeedbackTick += 1
        showCategoriesCopied = true
    }

    @ViewBuilder
    private func updateFrequencyActions(_ frequency: PodcastUpdateFrequency) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let text = frequency.shareText {
                HStack(spacing: 12) {
                    Button {
                        copyUpdateFrequency(text)
                    } label: {
                        Label("Copy update frequency", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy update frequency"))
                    .accessibilityHint(
                        String(localized: "Copies the same feed-provided update-frequency summary shown above to the pasteboard; display-only; does not change Keep updated or refresh")
                    )

                    ShareLink(
                        item: text,
                        subject: Text(feedDisplayTitle)
                    ) {
                        Label("Share update frequency", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share update frequency"))
                    .accessibilityHint(
                        String(localized: "Shares the same feed-provided update-frequency summary shown above as plain text; display-only; does not change Keep updated or refresh")
                    )
                }
            }

            // Distinct from combined update-frequency summary — exact Recurrence caption only; hide when rrule missing.
            if let caption = frequency.displayRruleCaption {
                HStack(spacing: 12) {
                    Button {
                        copyUpdateFrequencyRrule(caption)
                    } label: {
                        Label("Copy recurrence", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy recurrence"))
                    .accessibilityHint(
                        String(localized: "Copies the same Recurrence caption shown above to the pasteboard; display-only; does not change Keep updated or refresh")
                    )

                    ShareLink(
                        item: caption,
                        subject: Text(feedDisplayTitle)
                    ) {
                        Label("Share recurrence", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share recurrence"))
                    .accessibilityHint(
                        String(localized: "Shares the same Recurrence caption shown above as plain text; display-only; does not change Keep updated or refresh")
                    )
                }
            }

            // Distinct from combined update-frequency summary — exact Starts caption only; hide when dtstart missing.
            if let caption = frequency.displayDtstartCaption {
                HStack(spacing: 12) {
                    Button {
                        copyUpdateFrequencyDtstart(caption)
                    } label: {
                        Label("Copy start timestamp", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy start timestamp"))
                    .accessibilityHint(
                        String(localized: "Copies the same Starts caption shown above to the pasteboard; display-only; does not change Keep updated or refresh")
                    )

                    ShareLink(
                        item: caption,
                        subject: Text(feedDisplayTitle)
                    ) {
                        Label("Share start timestamp", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share start timestamp"))
                    .accessibilityHint(
                        String(localized: "Shares the same Starts caption shown above as plain text; display-only; does not change Keep updated or refresh")
                    )
                }
            }
        }
    }

    private func copyUpdateFrequency(_ text: String) {
        UIPasteboard.general.string = text
        copyUpdateFrequencyFeedbackTick += 1
        showUpdateFrequencyCopied = true
    }

    private func copyUpdateFrequencyRrule(_ caption: String) {
        UIPasteboard.general.string = caption
        copyUpdateFrequencyRruleFeedbackTick += 1
        showUpdateFrequencyRruleCopied = true
    }

    private func copyUpdateFrequencyDtstart(_ caption: String) {
        UIPasteboard.general.string = caption
        copyUpdateFrequencyDtstartFeedbackTick += 1
        showUpdateFrequencyDtstartCopied = true
    }

    @ViewBuilder
    private var itunesCompleteActions: some View {
        HStack(spacing: 12) {
            Button {
                copyItunesComplete()
            } label: {
                Label("Copy complete claim", systemImage: "doc.on.doc")
                    .font(.subheadline)
            }
            .accessibilityLabel(String(localized: "Copy complete claim"))
            .accessibilityHint(
                String(localized: "Copies the localized Complete claim and its feed-provided itunes:complete footnote to the pasteboard; display-only; does not change Keep updated or refresh")
            )

            ShareLink(
                item: displayItunesCompleteShareText,
                subject: Text(feedDisplayTitle)
            ) {
                Label("Share complete claim", systemImage: "square.and.arrow.up")
                    .font(.subheadline)
            }
            .accessibilityLabel(String(localized: "Share complete claim"))
            .accessibilityHint(
                String(localized: "Shares the localized Complete claim and its feed-provided itunes:complete footnote as plain text; display-only; does not change Keep updated or refresh")
            )
        }
    }

    private func copyItunesComplete() {
        UIPasteboard.general.string = displayItunesCompleteShareText
        copyItunesCompleteFeedbackTick += 1
        showItunesCompleteCopied = true
    }

    @ViewBuilder
    private var explicitActions: some View {
        HStack(spacing: 12) {
            Button {
                copyExplicit()
            } label: {
                Label("Copy explicit badge", systemImage: "doc.on.doc")
                    .font(.subheadline)
            }
            .accessibilityLabel(String(localized: "Copy explicit badge"))
            .accessibilityHint(
                String(localized: "Copies the localized Explicit badge shown above to the pasteboard; display-only; does not enforce content restrictions")
            )

            ShareLink(
                item: displayExplicitShareText,
                subject: Text(feedDisplayTitle)
            ) {
                Label("Share explicit badge", systemImage: "square.and.arrow.up")
                    .font(.subheadline)
            }
            .accessibilityLabel(String(localized: "Share explicit badge"))
            .accessibilityHint(
                String(localized: "Shares the localized Explicit badge shown above as plain text; display-only; does not enforce content restrictions")
            )
        }
    }

    private func copyExplicit() {
        UIPasteboard.general.string = displayExplicitShareText
        copyExplicitFeedbackTick += 1
        showExplicitCopied = true
    }

    @ViewBuilder
    private var blockedActions: some View {
        HStack(spacing: 12) {
            Button {
                copyBlocked()
            } label: {
                Label("Copy blocked claim", systemImage: "doc.on.doc")
                    .font(.subheadline)
            }
            .accessibilityLabel(String(localized: "Copy blocked claim"))
            .accessibilityHint(
                String(localized: "Copies the localized Blocked capsule and its directory footnote to the pasteboard; display-only; subscribe and play still work")
            )

            ShareLink(
                item: displayBlockedShareText,
                subject: Text(feedDisplayTitle)
            ) {
                Label("Share blocked claim", systemImage: "square.and.arrow.up")
                    .font(.subheadline)
            }
            .accessibilityLabel(String(localized: "Share blocked claim"))
            .accessibilityHint(
                String(localized: "Shares the localized Blocked capsule and its directory footnote as plain text; display-only; subscribe and play still work")
            )
        }
    }

    private func copyBlocked() {
        UIPasteboard.general.string = displayBlockedShareText
        copyBlockedFeedbackTick += 1
        showBlockedCopied = true
    }

    private func copyLastRefreshed(_ text: String) {
        UIPasteboard.general.string = text
        copyLastRefreshedFeedbackTick += 1
        showLastRefreshedCopied = true
    }

    @ViewBuilder
    private func mediumActions(_ medium: String) -> some View {
        HStack(spacing: 12) {
            Button {
                copyMedium(medium)
            } label: {
                Label("Copy medium", systemImage: "doc.on.doc")
                    .font(.subheadline)
            }
            .accessibilityLabel(String(localized: "Copy medium"))
            .accessibilityHint(
                String(localized: "Copies the same feed-provided medium string shown above to the pasteboard; display-only; no playback change or remapping")
            )

            ShareLink(
                item: medium,
                subject: Text(feedDisplayTitle)
            ) {
                Label("Share medium", systemImage: "square.and.arrow.up")
                    .font(.subheadline)
            }
            .accessibilityLabel(String(localized: "Share medium"))
            .accessibilityHint(
                String(localized: "Shares the same feed-provided medium string shown above as plain text; display-only; no playback change or remapping")
            )
        }
    }

    private func copyMedium(_ medium: String) {
        UIPasteboard.general.string = medium
        copyMediumFeedbackTick += 1
        showMediumCopied = true
    }

    @ViewBuilder
    private func itunesTypeActions(_ itunesType: String) -> some View {
        HStack(spacing: 12) {
            Button {
                copyItunesType(itunesType)
            } label: {
                Label("Copy podcast type", systemImage: "doc.on.doc")
                    .font(.subheadline)
            }
            .accessibilityLabel(String(localized: "Copy podcast type"))
            .accessibilityHint(
                String(localized: "Copies the same displayed Episodic, Serial, or feed-provided type string to the pasteboard; display-only; does not change sorting")
            )

            ShareLink(
                item: itunesType,
                subject: Text(feedDisplayTitle)
            ) {
                Label("Share podcast type", systemImage: "square.and.arrow.up")
                    .font(.subheadline)
            }
            .accessibilityLabel(String(localized: "Share podcast type"))
            .accessibilityHint(
                String(localized: "Shares the same displayed Episodic, Serial, or feed-provided type string as plain text; display-only; does not change sorting")
            )
        }
    }

    private func copyItunesType(_ itunesType: String) {
        UIPasteboard.general.string = itunesType
        copyItunesTypeFeedbackTick += 1
        showItunesTypeCopied = true
    }

    private func copyLockedOwner(_ owner: String) {
        UIPasteboard.general.string = owner
        copyLockedOwnerFeedbackTick += 1
        showLockedOwnerCopied = true
    }

    /// Feed-provided Podcast Index `podcast:guid` only — never invent / never derive from feed URL.
    private func copyPodcastGuid() {
        guard let guid = displayPodcastGuid else { return }
        UIPasteboard.general.string = guid
        copyPodcastGuidFeedbackTick += 1
        showPodcastGuidCopied = true
    }

    private func copyPodcastTitle(_ title: String) {
        guard let trimmed = EpisodeCopyLinks.trimmedFeedTitle(title) else { return }
        UIPasteboard.general.string = trimmed
        copyPodcastTitleFeedbackTick += 1
        showPodcastTitleCopied = true
    }

    private func copyTrailerTitle(_ title: String) {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        UIPasteboard.general.string = title
        copyTrailerTitleFeedbackTick += 1
        showTrailerTitleCopied = true
    }

    private func copyTrailerPubDate(_ pubDate: String) {
        let trimmed = pubDate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UIPasteboard.general.string = trimmed
        copyTrailerPubDateFeedbackTick += 1
        showTrailerPubDateCopied = true
    }

    private func copyTrailerSeason(_ seasonText: String) {
        guard !seasonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        UIPasteboard.general.string = seasonText
        copyTrailerSeasonFeedbackTick += 1
        showTrailerSeasonCopied = true
    }

    private func copyTrailerType(_ type: String) {
        guard !type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        UIPasteboard.general.string = type
        copyTrailerTypeFeedbackTick += 1
        showTrailerTypeCopied = true
    }

    private func copyTrailerLength(_ length: String) {
        guard !length.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        UIPasteboard.general.string = length
        copyTrailerLengthFeedbackTick += 1
        showTrailerLengthCopied = true
    }

    /// Channel podcast:trailer row — title, raw pubdate, optional season/type/byte size;
    /// Play via PlaybackService when enclosure-like, else openURL.
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

            if let type = trailer.displayType {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Trailer type"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                    Text(type)
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .accessibilityLabel("\(String(localized: "Trailer type")), \(type)")
                    HStack(spacing: 12) {
                        Button {
                            copyTrailerType(type)
                        } label: {
                            Label("Copy trailer type", systemImage: "doc.on.doc")
                                .font(.subheadline)
                        }
                        .accessibilityLabel(String(localized: "Copy trailer type"))
                        .accessibilityHint(
                            String(localized: "Copies the exact feed-provided trailer type as plain text")
                        )

                        ShareLink(
                            item: type,
                            subject: Text(title),
                            message: Text(String(localized: "Podcast trailer type from the feed."))
                        ) {
                            Label("Share trailer type", systemImage: "square.and.arrow.up")
                                .font(.subheadline)
                        }
                        .accessibilityLabel(String(localized: "Share trailer type"))
                        .accessibilityHint(
                            String(localized: "Shares the exact feed-provided trailer type as plain text")
                        )
                    }
                }
            }

            if let length = trailer.displayLengthLabel {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Trailer size"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                    Text(length)
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .accessibilityLabel("\(String(localized: "Trailer size")), \(length)")
                    HStack(spacing: 12) {
                        Button {
                            copyTrailerLength(length)
                        } label: {
                            Label("Copy trailer size", systemImage: "doc.on.doc")
                                .font(.subheadline)
                        }
                        .accessibilityLabel(String(localized: "Copy trailer size"))
                        .accessibilityHint(
                            String(localized: "Copies the exact displayed feed-provided trailer size as plain text")
                        )

                        ShareLink(
                            item: length,
                            subject: Text(title),
                            message: Text(String(localized: "Podcast trailer size from the feed."))
                        ) {
                            Label("Share trailer size", systemImage: "square.and.arrow.up")
                                .font(.subheadline)
                        }
                        .accessibilityLabel(String(localized: "Share trailer size"))
                        .accessibilityHint(
                            String(localized: "Shares the exact displayed feed-provided trailer size as plain text")
                        )
                    }
                }
            }

            HStack(spacing: 12) {
                Button {
                    copyTrailerTitle(title)
                } label: {
                    Label("Copy trailer title", systemImage: "doc.on.doc")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Copy trailer title"))
                .accessibilityHint(
                    String(localized: "Copies the displayed feed-provided trailer title to the pasteboard")
                )

                ShareLink(item: title) {
                    Label("Share trailer title", systemImage: "square.and.arrow.up")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Share trailer title"))
                .accessibilityHint(
                    String(localized: "Shares the displayed feed-provided trailer title as plain text")
                )
            }

            if let pubDate = trailer.displayPubDate {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Trailer publication date"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)

                    Text(pubDate)
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .accessibilityLabel(
                            "\(String(localized: "Trailer publication date")), \(pubDate)"
                        )

                    HStack(spacing: 12) {
                        Button {
                            copyTrailerPubDate(pubDate)
                        } label: {
                            Label("Copy trailer publication date", systemImage: "doc.on.doc")
                                .font(.subheadline)
                        }
                        .accessibilityLabel(String(localized: "Copy trailer publication date"))
                        .accessibilityHint(
                            String(localized: "Copies the feed-provided trailer publication date to the pasteboard")
                        )

                        ShareLink(
                            item: pubDate,
                            subject: Text(title),
                            message: Text(String(localized: "Podcast trailer publication date from the feed."))
                        ) {
                            Label("Share trailer publication date", systemImage: "square.and.arrow.up")
                                .font(.subheadline)
                        }
                        .accessibilityLabel(String(localized: "Share trailer publication date"))
                        .accessibilityHint(
                            String(localized: "Shares the feed-provided trailer publication date as plain text")
                        )
                    }
                }
            }

            if let season = trailer.season {
                let seasonText = String(localized: "Season \(season)")
                VStack(alignment: .leading, spacing: 6) {
                    Text(seasonText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("\(String(localized: "Trailer season")), \(seasonText)")

                    HStack(spacing: 12) {
                        Button {
                            copyTrailerSeason(seasonText)
                        } label: {
                            Label("Copy trailer season", systemImage: "doc.on.doc")
                                .font(.subheadline)
                        }
                        .accessibilityLabel(String(localized: "Copy trailer season"))
                        .accessibilityHint(
                            String(localized: "Copies the same displayed feed-provided trailer season to the pasteboard")
                        )

                        ShareLink(
                            item: seasonText,
                            subject: Text(title),
                            message: Text(String(localized: "Podcast trailer season from the feed."))
                        ) {
                            Label("Share trailer season", systemImage: "square.and.arrow.up")
                                .font(.subheadline)
                        }
                        .accessibilityLabel(String(localized: "Share trailer season"))
                        .accessibilityHint(
                            String(localized: "Shares the same displayed feed-provided trailer season as plain text")
                        )
                    }
                }
            }

            if let url = trailer.mediaURL {
                HStack(spacing: 12) {
                    if trailer.prefersInAppPlayback {
                        Button {
                            playOrOpenTrailer(trailer)
                        } label: {
                            Label("Play trailer", systemImage: "play.fill")
                                .font(.subheadline)
                        }
                        .accessibilityLabel(String(localized: "Play trailer"))
                        .accessibilityHint(String(localized: "Plays this feed-provided podcast:trailer in the app when the media URL looks playable, starting from the beginning so Skip intro does not clip it. Otherwise opens the URL in the system browser. No confirmation. Distinct from Open trailer. Does not mark played, change the queue, delete downloads, or alter subscriptions."))
                    } else {
                        Button {
                            playOrOpenTrailer(trailer)
                        } label: {
                            Label("Open trailer", systemImage: "safari")
                                .font(.subheadline)
                        }
                        .accessibilityLabel(String(localized: "Open trailer"))
                        .accessibilityHint(String(localized: "Opens this feed-provided podcast:trailer URL in the system browser. Shown when in-app play is not offered for this media URL. No confirmation. Distinct from Play trailer. Does not mark played, change the queue, delete downloads, or alter subscriptions."))
                    }

                    Button {
                        copyTrailerURL(url)
                    } label: {
                        Label("Copy trailer URL", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy trailer URL"))
                    .accessibilityHint(String(localized: "Copies this feed-provided podcast:trailer media URL to the pasteboard. No confirmation. Distinct from Play trailer, Open trailer, and Share trailer URL. Does not play the trailer, mark played, change the queue, delete downloads, or alter subscriptions."))

                    ShareLink(
                        item: url,
                        subject: Text(title),
                        message: Text(String(localized: "Podcast trailer URL from the feed."))
                    ) {
                        Label("Share trailer URL", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share trailer URL"))
                    .accessibilityHint(String(localized: "Opens the system share sheet with this feed-provided podcast:trailer media URL. No confirmation. Distinct from Play trailer, Open trailer, and Copy trailer URL. Does not play the trailer, mark played, change the queue, delete downloads, or alter subscriptions."))
                }
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
                    // A running, queued, or Wi-Fi-held download could only be stopped with
                    // Cancel all downloads. Tapping Waiting / the spinner cancels just this one.
                    if downloads.inProgress.contains(episode.id) {
                        downloads.cancelDownload(episode)
                    } else {
                        Task { await downloads.download(episode) }
                    }
                } label: {
                    if downloads.isWaitingDownload(episodeId: episode.id) {
                        Label("Waiting", systemImage: "clock")
                    } else if downloads.inProgress.contains(episode.id) {
                        ProgressView()
                    } else if downloads.isDownloaded(episode) {
                        Label("Downloaded", systemImage: "checkmark.circle.fill")
                    } else {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(episode.downloadUrl == nil)
                .accessibilityLabel(downloadAccessibilityLabel)
                .accessibilityHint(
                    downloads.isWaitingDownload(episodeId: episode.id)
                        ? String(localized: "Cancels this waiting download immediately. No confirmation. Does not delete completed offline files, and does not affect played status, queue, favorites, or archive. Distinct from Cancel all downloads and from Delete download.")
                        : downloads.inProgress.contains(episode.id)
                            ? String(localized: "Cancels this in-progress download immediately. No confirmation. Does not delete completed offline files, and does not affect played status, queue, favorites, or archive. Distinct from Cancel all downloads and from Delete download.")
                            : ""
                )

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
                        state.isPlayed ? String(localized: "Mark unplayed") : String(localized: "Mark played"),
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
                        ? String(localized: "Marks this episode as unplayed. No confirmation. Does not delete downloads, remove from queue, or stop playback.")
                        : String(localized: "Marks this episode as played. No confirmation. Removes it from the queue. May reset playback position and auto-delete the download when those settings are enabled.")
                )

                Button {
                    store.toggleFavorite(episode.id)
                } label: {
                    Label(
                        store.isFavorite(episode.id) ? String(localized: "Unfavorite") : String(localized: "Favorite"),
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
                        store.isArchived(episode.id) ? String(localized: "Restore") : String(localized: "Archive"),
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
                        ? String(localized: "Restores this episode from the archive. No confirmation. Does not delete downloads, remove from queue, unfavorite, or mark played.")
                        : String(localized: "Archives this episode and hides it from Inbox without marking it played. No confirmation. Does not delete downloads, remove from queue, or unfavorite.")
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
            .accessibilityHint(String(localized: "Seeks to the start of this episode and plays immediately. No confirmation. Does not skip intro, mark unplayed, change the queue, or delete downloads."))

            if let url = episode.websiteURL {
                Button {
                    openURL(url)
                } label: {
                    Label("Open episode website", systemImage: "safari")
                }
                .accessibilityLabel(String(localized: "Open episode website"))
                .accessibilityHint(String(localized: "Opens the feed-provided episode webpage http(s) link in the system browser — not an in-app WebView. No confirmation. Never uses the enclosure or podcast website URL. Distinct from Copy episode link, Copy media URL, and Share episode. Does not download, play, mark played, or change the queue."))

                Button {
                    copyEpisodeLink(url)
                } label: {
                    Label("Copy episode link", systemImage: "doc.on.doc")
                }
                .accessibilityLabel(String(localized: "Copy episode link"))
                .accessibilityHint(String(localized: "Copies the feed-provided episode webpage http(s) link to the pasteboard. No confirmation. Never silently copies the enclosure as the episode link. Distinct from Copy media URL and Share episode. Does not open the browser, download, play, mark played, or change the queue."))
            }
            EpisodeShareLinks.episodeLinkLabelStyle(episode: episode)
            if let rawMediaURL = episode.mediaURLString {
                Button {
                    copyMediaURL(rawMediaURL)
                } label: {
                    Label("Copy media URL", systemImage: "link")
                }
                .accessibilityLabel(String(localized: "Copy media URL"))
                .accessibilityHint(String(localized: "Copies the feed-provided episode media / enclosure http(s) URL to the pasteboard. No confirmation. Hidden for local file or local-folder URLs. Distinct from Copy episode link and Share episode. Does not download, play, mark played, or change the queue."))

                EpisodeShareLinks.mediaURLLabelStyle(episode: episode)
            }
            if let seasonEpisodeCaption = episode.seasonEpisodeCaption {
                Button {
                    copyEpisodeMetadata(
                        seasonEpisodeCaption,
                        message: String(localized: "Season and episode copied to the pasteboard.")
                    )
                } label: {
                    Label("Copy season and episode", systemImage: "doc.on.doc")
                }
                .accessibilityLabel(String(localized: "Copy season and episode"))
                .accessibilityHint(String(localized: "Copies the same season and episode caption shown above to the pasteboard; item metadata only; no numbers invented"))

                ShareLink(item: seasonEpisodeCaption, subject: Text(episode.title)) {
                    Label("Share season and episode", systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel(String(localized: "Share season and episode"))
                .accessibilityHint(String(localized: "Shares the same season and episode caption shown above as plain text; item metadata only; no numbers invented"))
            }
            if episode.isExplicit {
                let explicit = String(localized: "Explicit")
                Button {
                    copyEpisodeMetadata(
                        explicit,
                        message: String(localized: "Episode explicit badge copied to the pasteboard.")
                    )
                } label: {
                    Label("Copy episode explicit badge", systemImage: "doc.on.doc")
                }
                .accessibilityLabel(String(localized: "Copy episode explicit badge"))
                .accessibilityHint(String(localized: "Copies the localized Explicit badge shown above for this episode to the pasteboard; display-only; does not enforce content restrictions"))

                ShareLink(item: explicit, subject: Text(episode.title)) {
                    Label("Share episode explicit badge", systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel(String(localized: "Share episode explicit badge"))
                .accessibilityHint(String(localized: "Shares the localized Explicit badge shown above for this episode as plain text; display-only; does not enforce content restrictions"))
            }
            if let medium = episode.displayMedium {
                Button {
                    copyEpisodeMetadata(
                        medium,
                        message: String(localized: "Episode medium copied to the pasteboard.")
                    )
                } label: {
                    Label("Copy episode medium", systemImage: "doc.on.doc")
                }
                .accessibilityLabel(String(localized: "Copy episode medium"))
                .accessibilityHint(String(localized: "Copies the same item-provided medium string shown above to the pasteboard; display-only; no playback change or remapping"))

                ShareLink(item: medium, subject: Text(episode.title)) {
                    Label("Share episode medium", systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel(String(localized: "Share episode medium"))
                .accessibilityHint(String(localized: "Shares the same item-provided medium string shown above as plain text; display-only; no playback change or remapping"))
            }
            if let episodeType = episode.displayEpisodeType {
                Button {
                    copyEpisodeMetadata(
                        episodeType,
                        message: String(localized: "Episode type copied to the pasteboard.")
                    )
                } label: {
                    Label("Copy episode type", systemImage: "doc.on.doc")
                }
                .accessibilityLabel(String(localized: "Copy episode type"))
                .accessibilityHint(String(localized: "Copies the same item itunes:episodeType label shown above to the pasteboard; distinct from channel podcast:trailer"))

                ShareLink(item: episodeType, subject: Text(episode.title)) {
                    Label("Share episode type", systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel(String(localized: "Share episode type"))
                .accessibilityHint(String(localized: "Shares the same item itunes:episodeType label shown above as plain text; distinct from channel podcast:trailer"))
            }
            if dateOverride == nil, let publishDate = formattedPubDateCaption {
                Button {
                    copyEpisodeMetadata(
                        publishDate,
                        message: String(localized: "Episode publish date copied to the pasteboard.")
                    )
                } label: {
                    Label("Copy episode publish date", systemImage: "doc.on.doc")
                }
                .accessibilityLabel(String(localized: "Copy episode publish date"))
                .accessibilityHint(String(localized: "Copies the same publish-date caption shown in this episode row to the pasteboard; known feed metadata only; no date invented"))

                ShareLink(item: publishDate, subject: Text(episode.title)) {
                    Label("Share episode publish date", systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel(String(localized: "Share episode publish date"))
                .accessibilityHint(String(localized: "Shares the same publish-date caption shown in this episode row as plain text; known feed metadata only; no date invented"))
            }
            if let duration = formattedKnownDuration {
                Button {
                    copyEpisodeMetadata(
                        duration,
                        message: String(localized: "Episode duration copied to the pasteboard.")
                    )
                } label: {
                    Label("Copy episode duration", systemImage: "doc.on.doc")
                }
                .accessibilityLabel(String(localized: "Copy episode duration"))
                .accessibilityHint(String(localized: "Copies the same duration caption shown in this episode row to the pasteboard; feed or known playback metadata only; no length invented"))

                ShareLink(item: duration, subject: Text(episode.title)) {
                    Label("Share episode duration", systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel(String(localized: "Share episode duration"))
                .accessibilityHint(String(localized: "Shares the same duration caption shown in this episode row as plain text; feed or known playback metadata only; no length invented"))
            }
            if let size = formattedKnownByteSize {
                Button {
                    copyEpisodeMetadata(
                        size,
                        message: String(localized: "Episode file size copied to the pasteboard.")
                    )
                } label: {
                    Label("Copy episode file size", systemImage: "doc.on.doc")
                }
                .accessibilityLabel(String(localized: "Copy episode file size"))
                .accessibilityHint(String(localized: "Copies the same file-size caption shown in this episode row to the pasteboard; on-disk or feed enclosure metadata only; no size invented"))

                ShareLink(item: size, subject: Text(episode.title)) {
                    Label("Share episode file size", systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel(String(localized: "Share episode file size"))
                .accessibilityHint(String(localized: "Shares the same file-size caption shown in this episode row as plain text; on-disk or feed enclosure metadata only; no size invented"))
            }
            if let podcastTitle = EpisodeCopyLinks.trimmedFeedTitle(feedTitle) {
                Button {
                    copiedAlertMessage = EpisodeCopyLinks.copyPodcastTitle(podcastTitle)
                    copyURLFeedbackTick += 1
                    showCopiedAlert = true
                } label: {
                    Label("Copy podcast title", systemImage: "doc.on.doc")
                }
                .accessibilityLabel(String(localized: "Copy podcast title"))
                .accessibilityHint(String(localized: "Copies the trimmed podcast display title to the pasteboard; hidden when the title is empty; no title invented"))

                ShareLink(item: podcastTitle, subject: Text(podcastTitle)) {
                    Label("Share podcast title", systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel(String(localized: "Share podcast title"))
                .accessibilityHint(String(localized: "Shares the trimmed podcast display title as plain text; hidden when the title is empty; no title invented"))
            }
            if let title = EpisodeCopyLinks.trimmedTitle(for: episode) {
                Button {
                    copiedAlertMessage = EpisodeCopyLinks.copyEpisodeTitle(title)
                    copyURLFeedbackTick += 1
                    showCopiedAlert = true
                } label: {
                    Label("Copy episode title", systemImage: "doc.on.doc")
                }
                .accessibilityLabel(String(localized: "Copy episode title"))
                .accessibilityHint(String(localized: "Copies the trimmed episode title to the pasteboard; hidden when the title is empty; no title invented"))

                ShareLink(item: title, subject: Text(title)) {
                    Label("Share episode title", systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel(String(localized: "Share episode title"))
                .accessibilityHint(String(localized: "Shares the trimmed episode title as plain text; hidden when the title is empty; no title invented"))
            }
            if let titleAndPodcast = EpisodeCopyLinks.trimmedTitleAndPodcast(
                episode: episode,
                feedTitle: feedTitle
            ) {
                Button {
                    copiedAlertMessage = EpisodeCopyLinks.copyTitleAndPodcast(titleAndPodcast)
                    copyURLFeedbackTick += 1
                    showCopiedAlert = true
                } label: {
                    Label("Copy title and podcast", systemImage: "doc.on.doc")
                }
                .accessibilityLabel(String(localized: "Copy title and podcast"))
                .accessibilityHint(String(localized: "Copies the trimmed episode title and podcast display title as `title — podcast`; hidden unless both are present; no title invented"))

                ShareLink(item: titleAndPodcast, subject: Text(titleAndPodcast)) {
                    Label("Share title and podcast", systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel(String(localized: "Share title and podcast"))
                .accessibilityHint(String(localized: "Shares the trimmed episode title and podcast display title as `title — podcast` plain text; hidden unless both are present; no title invented"))
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
                    store.isFavorite(episode.id) ? String(localized: "Unfavorite") : String(localized: "Favorite"),
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
                    store.isArchived(episode.id) ? String(localized: "Restore") : String(localized: "Archive"),
                    systemImage: store.isArchived(episode.id) ? "arrow.uturn.backward" : "archivebox"
                )
            }
            Button {
                store.togglePlayed(episode.id)
            } label: {
                Label(
                    state.isPlayed ? String(localized: "Mark unplayed") : String(localized: "Mark played"),
                    systemImage: state.isPlayed ? "circle" : "checkmark.circle"
                )
            }
            Button {
                store.playNext(episode, currentlyPlayingId: playback.currentEpisode?.id)
            } label: {
                Label("Play Next", systemImage: "text.insert")
            }
            .accessibilityHint(
                String(localized: "Places this episode immediately after the currently playing queue item, or at the head if nothing is playing or current is not queued. Moves it if already queued — no duplicate. No confirmation. Queue lock does not block Play Next. Does not start playback, download, or mark played.")
            )
            Button {
                store.enqueue(episode)
            } label: {
                Label("Add to queue", systemImage: "text.append")
            }
            .accessibilityHint(
                String(localized: "Adds this episode to the end of the queue. No confirmation. Queue lock does not block enqueue. Does not start download or mark played.")
            )
            // Move to top/bottom = manual reorder; hidden when Queue lock is on (Play Next / enqueue stay).
            if let qi = queueIndex, !settings.queueLocked {
                if qi > 0 {
                    Button {
                        store.moveQueueItemToTop(episode)
                    } label: {
                        Label("Move to top", systemImage: "arrow.up.to.line")
                    }
                    .accessibilityLabel(String(localized: "Move to top"))
                    .accessibilityHint(String(localized: "Places this episode at the start of the queue. Does not seek or stop playback, change progress, mark played, or delete downloads. No confirmation."))
                }
                if qi < store.queue.count - 1 {
                    Button {
                        store.moveQueueItemToBottom(episode)
                    } label: {
                        Label("Move to bottom", systemImage: "arrow.down.to.line")
                    }
                    .accessibilityLabel(String(localized: "Move to bottom"))
                    .accessibilityHint(String(localized: "Places this episode at the end of the queue. Does not seek or stop playback, change progress, mark played, or delete downloads. No confirmation."))
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

    private func copyEpisodeMetadata(_ text: String, message: String) {
        UIPasteboard.general.string = text
        copiedAlertMessage = message
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
            .accessibilityHint(String(localized: "Opens the system share sheet with the episode title and best network link (episode page, enclosure, feed homepage, or feed URL). Local file URLs are not shared. Does not include a playback position — use Share with position for that."))
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

    /// Live playhead while this row is the loaded episode. Saved progress lags by about 5s.
    /// Other episodes, and a non-finite live value, stay on `playback.json`.
    /// Do not take the greater of the two: an unsaved rewind must not jump forward.
    private var displayPositionSeconds: Double {
        if playback.currentEpisode?.id == episode.id, playback.positionSeconds.isFinite {
            return max(0, playback.positionSeconds)
        }
        return state.positionSeconds
    }

    /// Bar duration only. A known feed or saved duration is never replaced by 0.
    /// The loaded episode may use a finite live duration when nothing is stored yet.
    private var progressBarDurationSeconds: Double? {
        if let known = knownDurationSeconds {
            return known
        }
        if playback.currentEpisode?.id == episode.id,
           playback.durationSeconds.isFinite,
           playback.durationSeconds > 0 {
            return playback.durationSeconds
        }
        return nil
    }

    /// Fraction of episode heard for the thin list ProgressView.
    /// Position is the live playhead for the loaded episode, otherwise `playback.json`.
    /// Duration may fall back to feed `itunes:duration` / media via `knownDurationSeconds`.
    /// Hidden (0) when unplayed (`position ≤ 1`), fully played (`isPlayed`), or duration unknown.
    private var progressFraction: Double {
        guard !state.isPlayed else { return 0 }
        let position = displayPositionSeconds
        // Match Resume / Continue listening: ignore sub-second noise.
        guard position > 1, let duration = progressBarDurationSeconds, duration > 0 else {
            return 0
        }
        return min(1, position / duration)
    }

    /// Remaining wall-clock seconds when in-progress with known duration; else `nil`.
    private var remainingSeconds: Double? {
        guard progressFraction > 0, let duration = knownDurationSeconds else { return nil }
        let left = duration - displayPositionSeconds
        guard left.isFinite, left > 0 else { return nil }
        return left
    }

    private var resumeLabel: String {
        if !state.isPlayed, displayPositionSeconds > 1 {
            return String(localized: "Resume")
        }
        return String(localized: "Play")
    }

    private var downloadAccessibilityLabel: String {
        if downloads.inProgress.contains(episode.id) {
            return String(localized: "Cancel download")
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
        } else if !state.isPlayed, displayPositionSeconds > 1 {
            // Duration unknown: no bar, but VoiceOver can still say the position.
            // For the loaded episode that is the live playhead, not the last save.
            if let formatted = PodcastEpisode.formatPlaybackPosition(displayPositionSeconds) {
                parts.append(String(localized: "At \(formatted)"))
            }
        }
        if downloads.isDownloaded(episode) {
            parts.append(String(localized: "Downloaded"))
        } else if downloads.isWaitingDownload(episodeId: episode.id) {
            parts.append(String(localized: "Waiting"))
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
        EpisodeCopyLinks.formattedPublishDate(for: episode)
    }

    /// Feed/media duration, then saved playback duration; hidden when unknown — never invents.
    private var knownDurationSeconds: Double? {
        EpisodeCopyLinks.knownDurationSeconds(
            for: episode,
            savedDurationSeconds: state.durationSeconds
        )
    }

    /// Same `m:ss` / `h:mm:ss` caption shown on episode metadata surfaces.
    private var formattedKnownDuration: String? {
        EpisodeCopyLinks.formattedDuration(
            for: episode,
            savedDurationSeconds: state.durationSeconds
        )
    }

    /// Prefer the on-disk copy's size, then feed enclosure size; hide when unknown.
    private var knownByteSize: Int64? {
        EpisodeCopyLinks.knownByteSize(for: episode, downloads: downloads)
    }

    /// Same compact KB/MB/GB caption shown on episode metadata surfaces.
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
            if let caption = frequency.displayRruleCaption {
                Text(caption)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let caption = frequency.displayDtstartCaption {
                Text(caption)
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
