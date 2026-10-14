import SwiftUI
import UIKit

struct SubscriptionsView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var parental: ParentalControls
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var downloads: DownloadService
    @Environment(\.openURL) private var openURL
    @ObservedObject private var notificationDeepLink = NewEpisodeNotificationCoordinator.deepLink
    @State private var path = NavigationPath()
    @State private var lastHandledFeedOpenToken: UUID?
    @State private var showAdd = false
    @State private var showOpmlSheet = false
    @State private var showAddPINGate = false
    @State private var showDiscoverPINGate = false
    @State private var navigateToDiscover = false
    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var tagFilter: SubscriptionTagFilter = .all
    @State private var groupByTag = true
    @State private var feedPendingUnsubscribe: PodcastFeed?
    @State private var showUnpinAllConfirm = false
    @State private var showCopiedAlert = false
    @State private var copiedAlertMessage = ""
    @State private var copyFeedbackTick = 0

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    /// Local nickname (`FeedSettings.customTitle`) when set, else RSS title.
    private func feedDisplayTitle(_ feed: PodcastFeed) -> String {
        store.displayTitle(for: feed)
    }


    /// Client-side list order after search/category/language/tag filters (no drag-reorder of subscriptions).
    /// Author / language: A–Z by feed-provided `displayAuthor` / `displayLanguage`; missing values last; title tiebreak.
    /// Most unplayed: descending per-feed unplayed count (`!isPlayed && !isArchived`, same as badges /
    /// Inbox / `unplayedCountsByFeedId`); equal counts → title A–Z tiebreak.
    /// Recently / Least recently refreshed: by `lastRefreshedAtEpochMs` (successful network only);
    /// nil / local-folder last — never invent; title tiebreak.
    /// After the chosen `subscriptionsSort`, **pinned** feeds (`FeedSettings.isPinned`) are partitioned
    /// first (stable among pinned / unpinned by the same sort key). Local preference only — not a
    /// separate Picker sort mode. Flat-list partition runs before grouping; tag sections inherit
    /// that order (pinned still first within each section).
    private func sortedFeeds(_ feeds: [PodcastFeed]) -> [PodcastFeed] {
        let sorted: [PodcastFeed]
        switch settings.subscriptionsSort {
        case .recentlyUpdated:
            sorted = feeds.sorted { lhs, rhs in
                let l = lhs.episodes.compactMap(\.pubDateEpochMs).max() ?? Int64.min
                let r = rhs.episodes.compactMap(\.pubDateEpochMs).max() ?? Int64.min
                if l != r { return l > r }
                return feedDisplayTitle(lhs).localizedCaseInsensitiveCompare(feedDisplayTitle(rhs)) == .orderedAscending
            }
        case .alphabetical:
            sorted = feeds.sorted {
                feedDisplayTitle($0).localizedCaseInsensitiveCompare(feedDisplayTitle($1)) == .orderedAscending
            }
        case .byAuthor:
            sorted = feeds.sorted { lhs, rhs in
                switch (lhs.displayAuthor, rhs.displayAuthor) {
                case (nil, nil):
                    return feedDisplayTitle(lhs).localizedCaseInsensitiveCompare(feedDisplayTitle(rhs)) == .orderedAscending
                case (nil, _):
                    return false
                case (_, nil):
                    return true
                case let (l?, r?):
                    let cmp = l.localizedCaseInsensitiveCompare(r)
                    if cmp != .orderedSame { return cmp == .orderedAscending }
                    return feedDisplayTitle(lhs).localizedCaseInsensitiveCompare(feedDisplayTitle(rhs)) == .orderedAscending
                }
            }
        case .byLanguage:
            sorted = feeds.sorted { lhs, rhs in
                switch (lhs.displayLanguage, rhs.displayLanguage) {
                case (nil, nil):
                    return feedDisplayTitle(lhs).localizedCaseInsensitiveCompare(feedDisplayTitle(rhs)) == .orderedAscending
                case (nil, _):
                    return false
                case (_, nil):
                    return true
                case let (l?, r?):
                    let cmp = l.localizedCaseInsensitiveCompare(r)
                    if cmp != .orderedSame { return cmp == .orderedAscending }
                    return feedDisplayTitle(lhs).localizedCaseInsensitiveCompare(feedDisplayTitle(rhs)) == .orderedAscending
                }
            }
        case .mostUnplayed:
            // Same definition as row badges / Inbox (`!isPlayed && !isArchived`; missing = 0).
            let counts = store.unplayedCountsByFeedId()
            sorted = feeds.sorted { lhs, rhs in
                let l = counts[lhs.id] ?? 0
                let r = counts[rhs.id] ?? 0
                if l != r { return l > r }
                return feedDisplayTitle(lhs).localizedCaseInsensitiveCompare(feedDisplayTitle(rhs)) == .orderedAscending
            }
        case .recentlyRefreshed:
            // Newest successful network stamp first; nil / local-folder last (never invent).
            sorted = feeds.sorted { lhs, rhs in
                switch (lhs.lastRefreshedAtEpochMs, rhs.lastRefreshedAtEpochMs) {
                case (nil, nil):
                    return feedDisplayTitle(lhs).localizedCaseInsensitiveCompare(feedDisplayTitle(rhs)) == .orderedAscending
                case (nil, _):
                    return false
                case (_, nil):
                    return true
                case let (l?, r?):
                    if l != r { return l > r }
                    return feedDisplayTitle(lhs).localizedCaseInsensitiveCompare(feedDisplayTitle(rhs)) == .orderedAscending
                }
            }
        case .leastRecentlyRefreshed:
            // Oldest successful network stamp first; nil / local-folder last (never invent).
            sorted = feeds.sorted { lhs, rhs in
                switch (lhs.lastRefreshedAtEpochMs, rhs.lastRefreshedAtEpochMs) {
                case (nil, nil):
                    return feedDisplayTitle(lhs).localizedCaseInsensitiveCompare(feedDisplayTitle(rhs)) == .orderedAscending
                case (nil, _):
                    return false
                case (_, nil):
                    return true
                case let (l?, r?):
                    if l != r { return l < r }
                    return feedDisplayTitle(lhs).localizedCaseInsensitiveCompare(feedDisplayTitle(rhs)) == .orderedAscending
                }
            }
        }
        // Invisible pin partition on every existing sort (not a new Picker case).
        let pinned = sorted.filter { store.isPinned(feedId: $0.id) }
        let unpinned = sorted.filter { !store.isPinned(feedId: $0.id) }
        return pinned + unpinned
    }

    /// Visible subscriptions after search; empty query shows full list under current sort.
    /// Matches feed **display title** (customTitle ?? RSS), optional **descriptionText**, optional **author**, optional **language**,
    /// and optional **categories** (`PodcastStore.matchingFeeds`).
    private var searchFilteredFeeds: [PodcastFeed] {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: [PodcastFeed]
        if q.isEmpty {
            base = store.feeds
        } else {
            base = store.matchingFeeds(query: q)
        }
        return sortedFeeds(base)
    }

    private var isSearchFiltering: Bool {
        !debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Bound category chip from `AppSettings` (empty = All). Library categories only — never invent.
    private var categoryFilter: SubscriptionCategoryFilter {
        SubscriptionCategoryFilter.fromStorage(settings.subscriptionsCategoryFilter)
    }

    private var isCategoryFiltering: Bool {
        if case .category = categoryFilter { return true }
        return false
    }

    /// Unique `itunes:category` texts present on stored feeds (after refresh). Empty → hide category chips.
    private var libraryCategories: [String] {
        FeedTags.uniqueSorted(store.feeds.flatMap(\.displayCategories))
    }

    /// Search → category (AND). Feeds with empty categories never match a specific category chip.
    private var categoryFilteredFeeds: [PodcastFeed] {
        let base = searchFilteredFeeds
        guard isCategoryFiltering else { return base }
        return base.filter { categoryFilter.matches($0) }
    }

    /// Bound language chip from `AppSettings` (empty = All). Library language codes only — never invent.
    private var languageFilter: SubscriptionLanguageFilter {
        SubscriptionLanguageFilter.fromStorage(settings.subscriptionsLanguageFilter)
    }

    private var isLanguageFiltering: Bool {
        if case .language = languageFilter { return true }
        return false
    }

    /// Unique feed-provided language codes present on stored feeds (after refresh). Empty → hide language chips.
    /// Sorted by localized display name (A–Z); codes kept for storage / match.
    private var libraryLanguages: [String] {
        let codes = store.feeds.compactMap(\.languageCode)
        let unique = FeedTags.uniqueSorted(codes)
        return unique.sorted {
            FeedLanguageFormatting.displayName(for: $0)
                .localizedCaseInsensitiveCompare(FeedLanguageFormatting.displayName(for: $1))
                == .orderedAscending
        }
    }

    /// Search → category → language (AND). Feeds with empty language never match a specific language chip.
    private var languageFilteredFeeds: [PodcastFeed] {
        let base = categoryFilteredFeeds
        guard isLanguageFiltering else { return base }
        return base.filter { languageFilter.matches($0) }
    }

    /// Search → category → language → tag/pin (AND). Remaining-time / unplayed bars use this visible set.
    /// `.pinned` is session `@State` like other tag chips (not a sort mode); pin partition still
    /// applies within the filtered set via `sortedFeeds`.
    private var tagFilteredFeeds: [PodcastFeed] {
        let base = languageFilteredFeeds
        switch tagFilter {
        case .all:
            return base
        case .pinned:
            return base.filter { store.isPinned(feedId: $0.id) }
        case .untagged:
            return base.filter { store.tags(for: $0.id).isEmpty }
        case .tag(let name):
            return base.filter { feed in
                store.tags(for: feed.id).contains(where: { FeedTags.equal($0, name) })
            }
        }
    }

    /// Sections when grouping is on and filter is All (multi-tag feeds appear under each tag).
    /// Feeds within each section follow `subscriptionsSort` + pin partition (inherited from
    /// `languageFilteredFeeds` / flat-list order before grouping — pinned still first within section).
    private var groupedSections: [(title: String, feeds: [PodcastFeed])] {
        guard tagFilter == .all, groupByTag, !store.allTags.isEmpty else {
            return [("Podcasts", tagFilteredFeeds)]
        }
        var sections: [(title: String, feeds: [PodcastFeed])] = []
        for tag in store.allTags {
            let feeds = languageFilteredFeeds.filter { feed in
                store.tags(for: feed.id).contains(where: { FeedTags.equal($0, tag) })
            }
            if !feeds.isEmpty {
                sections.append((tag, feeds))
            }
        }
        let untagged = languageFilteredFeeds.filter { store.tags(for: $0.id).isEmpty }
        if !untagged.isEmpty {
            sections.append(("Untagged", untagged))
        }
        return sections
    }

    /// Any subscribed feed with Keep at top (`FeedSettings.isPinned`). Drives Pinned chip visibility.
    private var hasAnyPinnedSubscription: Bool {
        store.feeds.contains { store.isPinned(feedId: $0.id) }
    }

    /// Plain-text list of the **full** subscriptions library — not search / category / language / tag /
    /// Pinned-chip / UI `subscriptionsSort` / pin-partition filtered. Display title A–Z (empty last; id tiebreak).
    private var subscriptionsPlainText: String {
        SubscriptionsExport.plainText(feeds: store.feeds) { store.displayTitle(for: $0) }
    }

    /// Enabled when the full library is non-empty (read-only export).
    private var canExportSubscriptions: Bool {
        !store.feeds.isEmpty
    }

    /// “Subscriptions” header + body for system share sheet (same body as Copy).
    private var subscriptionsShareText: String {
        SubscriptionsExport.shareText(feeds: store.feeds) { store.displayTitle(for: $0) }
    }

    /// Count of subscribed feeds with Keep at top — drives Unpin all enablement + confirm title.
    private var pinnedSubscriptionCount: Int {
        store.feeds.filter { store.isPinned(feedId: $0.id) }.count
    }

    private var filterChips: [SubscriptionTagFilter] {
        var chips: [SubscriptionTagFilter] = [.all]
        // Pinned sits with All / tags / Untagged; hide when no Keep-at-top feeds remain.
        if hasAnyPinnedSubscription {
            chips.append(.pinned)
        }
        chips.append(contentsOf: store.allTags.map { .tag($0) })
        if !store.untaggedFeeds.isEmpty || store.allTags.isEmpty == false {
            chips.append(.untagged)
        }
        return chips
    }

    private var categoryFilterChips: [SubscriptionCategoryFilter] {
        var chips: [SubscriptionCategoryFilter] = [.all]
        chips.append(contentsOf: libraryCategories.map { .category($0) })
        return chips
    }

    private var languageFilterChips: [SubscriptionLanguageFilter] {
        var chips: [SubscriptionLanguageFilter] = [.all]
        chips.append(contentsOf: libraryLanguages.map { .language($0) })
        return chips
    }

    /// Single-pass map from `PodcastStore.unplayedRemainingByFeedId()` (missing = 0 /
    /// no remaining). Supplies both per-row unplayed **badge** counts and **per-feed remaining**.
    /// Touches live `PlaybackService` so remaining refreshes while listening (store reads the
    /// same weak `playback` for duration/position).
    private var unplayedRemainingByFeedId: [UUID: FeedUnplayedRemainingSummary] {
        _ = playback.currentEpisode?.id
        _ = playback.positionSeconds
        _ = playback.durationSeconds
        // Observe remaining-time speed prefs so per-feed / list bars refresh when toggled.
        _ = settings.remainingTimeRespectsSpeed
        _ = settings.defaultPlaybackSpeed
        return store.unplayedRemainingByFeedId()
    }

    /// AntennaPod-like info bar: unplayed count + remaining over unplayed episodes of
    /// **visible** subscriptions (search + category + language + tag). Built by summing per-feed summaries from
    /// `unplayedRemainingByFeedId` over **unique** `tagFilteredFeeds` (multi-tag Group by tag
    /// does not double-count). Same `!isPlayed && !isArchived` definition as per-row badges /
    /// Inbox / per-feed row remaining. Full stored feed catalogs — **not** the All Episodes
    /// newest-500 soft cap. Remaining per episode = `max(0, duration − position)` when
    /// duration known; **unknown duration skipped** (tilde when any skipped); live player
    /// when current. Wall-clock by default; optional Remaining time respects speed divides by feed/default speed (estimate). Distinct from Inbox tab
    /// remaining (`inboxSort` / full Inbox). Hidden when no visible feeds or no unplayed
    /// episodes among them.
    private func subscriptionsRemainingInfoLabel(_ summary: EpisodeRemainingTime.Summary) -> String? {
        EpisodeRemainingTime.unplayedInfoBarLabel(for: summary)
    }

    private func subscriptionsRemainingAccessibilityLabel(_ summary: EpisodeRemainingTime.Summary) -> String {
        guard let label = subscriptionsRemainingInfoLabel(summary) else { return "" }
        var parts = [String(localized: "Subscriptions unplayed remaining time \(label)")]
        let unknown = summary.unknownCount
        if unknown > 0 {
            parts.append(String(localized: "Remaining time excludes \(unknown) episode(s) with unknown duration"))
        }
        if isSearchFiltering || isCategoryFiltering || isLanguageFiltering || tagFilter != .all {
            parts.append(String(localized: "Subscriptions remaining time covers visible podcasts only (search, tag, category, or language filter), not the full library"))
        }
        return parts.joined(separator: ". ")
    }

    /// VoiceOver hint for the Subscriptions unplayed remaining bar. The visible
    /// label stays the count and time. This says whether that time is wall-clock
    /// or divided by podcast/default speed, and what the bar is not.
    private var subscriptionsRemainingAccessibilityHint: String {
        if settings.remainingTimeRespectsSpeed {
            return String(localized: "Estimate. Remaining time respects speed is on, so each episode is divided by that podcast’s playback speed, or Default speed, never below 0.5. This is not the live session rate and not Volume boost. Unplayed means not played and not archived, over each visible podcast’s stored episodes, not the All Episodes newest-500 cap. Group by tag counts each podcast once. Unknown durations are left out and no time is invented. The episode that is playing uses the live position, but the divisor stays the podcast or default speed. This is not the Inbox remaining bar, the mini player, or Lock Screen. It does not play, download, or mark episodes played.")
        }
        return String(localized: "Wall-clock remaining. Remaining time respects speed is off, so playback speed does not change this total. Unplayed means not played and not archived, over each visible podcast’s stored episodes, not the All Episodes newest-500 cap. Group by tag counts each podcast once. Unknown durations are left out and no time is invented. The episode that is playing uses the live position. This is not the Inbox remaining bar, the mini player, or Lock Screen. It does not play, download, or mark episodes played.")
    }

    /// `remainingByFeedId` is the body's single `unplayedRemainingByFeedId` pass; reading the
    /// property per feed here rescanned every feed's episodes once per visible feed.
    private func subscriptionsRemainingSummary(
        _ remainingByFeedId: [UUID: FeedUnplayedRemainingSummary]
    ) -> EpisodeRemainingTime.Summary {
        var episodeCount = 0
        var remaining = 0.0
        var known = 0
        var unknown = 0
        for feed in tagFilteredFeeds {
            guard let s = remainingByFeedId[feed.id] else { continue }
            episodeCount += s.unplayedCount
            remaining += s.remainingSeconds
            known += s.knownCount
            unknown += s.unknownCount
        }
        return EpisodeRemainingTime.Summary(
            episodeCount: episodeCount,
            remainingSeconds: remaining,
            knownCount: known,
            unknownCount: unknown
        )
    }

    // List split from the modifier chain: together they exceed the CI type-checker time limit.
    private var subscriptionsList: some View {
        List {
            // One pass over every feed's episodes per body (the body reruns on each 0.5s
            // playback tick); the info bar and every row read this same map.
            let remainingByFeedId = unplayedRemainingByFeedId
            let remainingSummary = subscriptionsRemainingSummary(remainingByFeedId)
            // AntennaPod-like subscriptions info bar (unplayed remaining over visible feeds).
            // Per-feed remaining also on each row (same map); unique feeds when grouped by tag.
            if let remainingLabel = subscriptionsRemainingInfoLabel(remainingSummary) {
                Section {
                    Text(remainingLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(subscriptionsRemainingAccessibilityLabel(remainingSummary))
                        .accessibilityHint(subscriptionsRemainingAccessibilityHint)
                }
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
            }

            Section("Library") {
                NavigationLink {
                    AllEpisodesView()
                } label: {
                    Label("Episodes", systemImage: "list.bullet.rectangle")
                }
                NavigationLink {
                    FavoritesView()
                } label: {
                    Label("Favorites", systemImage: "star")
                }
                NavigationLink {
                    BookmarksView()
                } label: {
                    Label("Bookmarks", systemImage: "bookmark")
                }
                NavigationLink {
                    ArchivedView()
                } label: {
                    Label("Archived", systemImage: "archivebox")
                }
                NavigationLink {
                    HistoryView()
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                NavigationLink {
                    StatisticsView()
                } label: {
                    Label("Statistics", systemImage: "chart.bar.doc.horizontal")
                }
                NavigationLink {
                    EchoView()
                } label: {
                    Label("Echo", systemImage: "sparkles.rectangle.stack")
                }
                Button {
                    if parental.needsPINForAddDiscover {
                        showDiscoverPINGate = true
                    } else {
                        navigateToDiscover = true
                    }
                } label: {
                    HStack {
                        Label("Discover", systemImage: "chart.bar")
                        Spacer()
                        if parental.needsPINForAddDiscover {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .tint(.primary)
            }

            if !store.feeds.isEmpty, !libraryCategories.isEmpty || isCategoryFiltering {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(categoryFilterChips) { chip in
                                TagFilterChip(
                                    title: chip.label,
                                    selected: categoryFilter == chip,
                                    accessibilityHint: String(localized: "Filters the Subscriptions list by category")
                                ) {
                                    settings.subscriptionsCategoryFilter = chip.storageValue
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                } header: {
                    Text("Categories")
                }
            }

            if !store.feeds.isEmpty, !libraryLanguages.isEmpty || isLanguageFiltering {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(languageFilterChips) { chip in
                                TagFilterChip(
                                    title: chip.label,
                                    selected: languageFilter == chip,
                                    accessibilityHint: String(localized: "Filters the Subscriptions list by language")
                                ) {
                                    settings.subscriptionsLanguageFilter = chip.storageValue
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                } header: {
                    Text("Languages")
                }
            }

            if !store.feeds.isEmpty, !store.allTags.isEmpty || hasAnyPinnedSubscription || tagFilter != .all {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(filterChips) { chip in
                                TagFilterChip(
                                    title: chip.label,
                                    selected: tagFilter == chip,
                                    accessibilityHint: chipAccessibilityHint(chip)
                                ) {
                                    tagFilter = chip
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

                    // Group by tag only for All (Pinned / tag / Untagged stay flat — same gate as grouping).
                    if tagFilter == .all {
                        Toggle("Group by tag", isOn: $groupByTag)
                            .accessibilityLabel(String(localized: "Group by tag"))
                            .accessibilityValue(groupByTagAccessibilityValue)
                            .accessibilityHint(groupByTagAccessibilityHint)
                    }
                } header: {
                    Text("Tags")
                }
            }

            if store.feeds.isEmpty {
                ContentUnavailableView(
                    "No subscriptions",
                    systemImage: "dot.radiowaves.left.and.right",
                    description: Text("Search Apple Podcasts, open Discover for charts, add by feed URL, pick a local Folder, or import an OPML file from Files (Add podcast → OPML).")
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(localized: "No subscriptions"))
                .accessibilityValue(subscriptionsEmptyStateAccessibilityValue)
            } else if tagFilteredFeeds.isEmpty {
                ContentUnavailableView(
                    "No matching podcasts",
                    systemImage: "magnifyingglass",
                    description: Text(subscriptionsEmptyFilterMessage)
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(localized: "No matching podcasts"))
                .accessibilityValue(subscriptionsEmptyStateAccessibilityValue)
                .accessibilityHint(subscriptionsNoMatchAccessibilityHint)
            } else {
                ForEach(groupedSections, id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.feeds) { feed in
                            feedRow(feed, summary: remainingByFeedId[feed.id])
                        }
                    }
                }
            }
        }
    }

    // Toolbar split from the body chain: together they exceed the CI type-checker time limit.
    @ToolbarContentBuilder
    private var subscriptionsToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await store.refreshAllFeeds() }
            } label: {
                if store.isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(store.isLoading || store.feeds.isEmpty)
            .accessibilityLabel(String(localized: "Refresh all"))
            .accessibilityHint(
                String(localized: "Refreshes every subscribed podcast that participates in Keep updated. Podcasts set to Keep updated Never are skipped; swipe Refresh on a row still refreshes that podcast alone. Uses the full subscriptions library, not search or filter. Feed refresh is not limited by the Wi‑Fi-only toggles and may use cellular. Does not invent episodes; Auto-download may enqueue newly appeared ones after successful refreshes. Distinct from Rescan folder.")
            )
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                if parental.needsPINForAddDiscover {
                    showAddPINGate = true
                } else {
                    showAdd = true
                }
            } label: {
                Image(systemName: parental.needsPINForAddDiscover ? "plus.circle" : "plus")
            }
            .accessibilityLabel(
                parental.needsPINForAddDiscover
                    ? String(localized: "Add podcast (PIN required)")
                    : String(localized: "Add podcast")
            )
        }
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showOpmlSheet = true
            } label: {
                Image(systemName: "arrow.up.arrow.down.square")
            }
            .accessibilityLabel(String(localized: "Import or export OPML"))
        }
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Picker(selection: $settings.subscriptionsSort) {
                    ForEach(SubscriptionsSort.allCases) { sort in
                        Label(sort.label, systemImage: sort.systemImage)
                            .tag(sort)
                    }
                } label: {
                    Text("Sort")
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .accessibilityLabel(String(localized: "Sort subscriptions"))
            .accessibilityValue(subscriptionsSortAccessibilityValue)
            .accessibilityHint(subscriptionsSortAccessibilityHint)
        }
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Button {
                    copySubscriptions()
                } label: {
                    Label("Copy subscriptions", systemImage: "doc.plaintext")
                }
                // Full library (not search/category/language/tag/Pinned/UI sort/pin partition).
                .disabled(!canExportSubscriptions)
                .accessibilityLabel(String(localized: "Copy subscriptions"))
                .accessibilityHint(
                    String(localized: "Copies the full subscriptions list to the pasteboard as plain text. Not OPML. Ignores search and filters.")
                )

                ShareLink(
                    item: subscriptionsShareText,
                    subject: Text(String(localized: "Subscriptions"))
                ) {
                    Label("Share subscriptions", systemImage: "square.and.arrow.up")
                }
                // Same gates as Copy subscriptions — full library plain text.
                .disabled(!canExportSubscriptions)
                .accessibilityLabel(String(localized: "Share subscriptions"))
                .accessibilityHint(
                    String(localized: "Opens the system share sheet with the full subscriptions list as plain text. Not OPML. Ignores search and filters.")
                )

                Button {
                    showUnpinAllConfirm = true
                } label: {
                    Label("Unpin all", systemImage: "pin.slash")
                }
                .disabled(pinnedSubscriptionCount == 0)
                .accessibilityLabel(String(localized: "Unpin all"))
                .accessibilityHint(String(localized: "Clears Keep at top for every pinned podcast. Does not unsubscribe, change tags, or change sort preference."))
            } label: {
                Label("Subscriptions actions", systemImage: "ellipsis.circle")
            }
            .accessibilityLabel(String(localized: "Subscriptions actions"))
            .accessibilityHint(
                String(localized: "Copy subscriptions, share subscriptions, or unpin all")
            )
            .disabled(store.feeds.isEmpty)
        }
        ToolbarItem(placement: .topBarLeading) {
            NavigationLink {
                ManageTagsView()
            } label: {
                Image(systemName: "tag")
            }
            .accessibilityLabel(String(localized: "Manage tags"))
            .accessibilityHint(String(localized: "Opens Manage tags to rename or delete tag labels across all podcasts. Rename updates every podcast using that name. Delete removes the tag from those podcasts but does not unsubscribe or delete downloads. Does not export OPML, start sync, or change playback."))
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            subscriptionsList
            .navigationTitle("Subscriptions")
            .searchable(text: $searchText, prompt: "Search subscriptions")
            .onChange(of: searchText) { _, newValue in
                scheduleFilter(for: newValue)
            }
            .onDisappear {
                debounceTask?.cancel()
            }
            .navigationDestination(for: PodcastFeed.self) { feed in
                FeedDetailView(feed: feed)
            }
            .refreshable {
                await store.refreshAllFeeds()
            }
            .toolbar { subscriptionsToolbar }
            .sheet(isPresented: $showAdd) {
                AddFeedView()
            }
            .navigationDestination(isPresented: $navigateToDiscover) {
                TopListsView()
            }
            .sheet(isPresented: $showAddPINGate) {
                ParentalPINPromptSheet(
                    title: String(localized: "Parental controls"),
                    message: String(localized: "Enter your PIN to add or discover podcasts."),
                    onCancel: { showAddPINGate = false },
                    onSuccess: { pin in
                        if parental.unlockSession(with: pin) {
                            showAddPINGate = false
                            showAdd = true
                            return true
                        }
                        return false
                    }
                )
            }
            .sheet(isPresented: $showDiscoverPINGate) {
                ParentalPINPromptSheet(
                    title: String(localized: "Parental controls"),
                    message: String(localized: "Enter your PIN to open Discover."),
                    onCancel: { showDiscoverPINGate = false },
                    onSuccess: { pin in
                        if parental.unlockSession(with: pin) {
                            showDiscoverPINGate = false
                            navigateToDiscover = true
                            return true
                        }
                        return false
                    }
                )
            }
            .sheet(isPresented: $showOpmlSheet) {
                NavigationStack {
                    Form {
                        OpmlImportExportSection()
                    }
                    .navigationTitle("OPML")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showOpmlSheet = false }
                        }
                    }
                }
            }
            .overlay {
                if store.isLoading {
                    ProgressView(store.refreshProgressLabel)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel(store.refreshProgressLabel)
                }
            }
            .onChange(of: store.tagsByFeedId) { _, _ in
                // Drop filter if the selected tag disappeared.
                if case .tag(let name) = tagFilter,
                   !store.allTags.contains(where: { FeedTags.equal($0, name) }) {
                    tagFilter = .all
                }
            }
            .onChange(of: store.feedSettingsById) { _, _ in
                resetPinnedFilterIfNeeded()
            }
            .onChange(of: store.feeds) { _, _ in
                // Drop category filter if that category is no longer present on any stored feed.
                if case .category(let name) = categoryFilter,
                   !libraryCategories.contains(where: { FeedTags.equal($0, name) }) {
                    settings.subscriptionsCategoryFilter = ""
                }
                // Drop language filter if that language code is no longer present on any stored feed.
                if case .language(let code) = languageFilter,
                   !libraryLanguages.contains(where: { FeedTags.equal($0, code) }) {
                    settings.subscriptionsLanguageFilter = ""
                }
                resetPinnedFilterIfNeeded()
            }
            .onAppear {
                resetPinnedFilterIfNeeded()
                consumePendingFeedOpenIfNeeded()
            }
            .onChange(of: notificationDeepLink.feedOpenToken) { _, _ in
                consumePendingFeedOpenIfNeeded()
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
                "Unpin \(pinnedSubscriptionCount) podcasts?",
                isPresented: $showUnpinAllConfirm,
                titleVisibility: .visible
            ) {
                Button("Unpin all") {
                    store.unpinAll()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Clears Keep at top for every pinned podcast. Does not unsubscribe, change tags, or change sort preference.")
            }
            .confirmationDialog(
                "Unsubscribe?",
                isPresented: Binding(
                    get: { feedPendingUnsubscribe != nil },
                    set: { if !$0 { feedPendingUnsubscribe = nil } }
                ),
                titleVisibility: .visible,
                presenting: feedPendingUnsubscribe
            ) { feed in
                let feedDownloadCount = downloads.downloads(forFeed: feed).count
                let feedDownloadSize = DownloadStorageUsage.formatBytes(
                    downloads.downloadsByteSize(forFeed: feed)
                )
                Button("Unsubscribe", role: .destructive) {
                    store.unsubscribe(feed)
                    feedPendingUnsubscribe = nil
                }
                if feedDownloadCount > 0 {
                    Button(
                        "Unsubscribe and delete \(feedDownloadCount) downloads (\(feedDownloadSize))",
                        role: .destructive
                    ) {
                        downloads.deleteDownloads(forFeed: feed)
                        store.unsubscribe(feed)
                        feedPendingUnsubscribe = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    feedPendingUnsubscribe = nil
                }
            } message: { feed in
                let feedDownloadCount = downloads.downloads(forFeed: feed).count
                let feedDownloadSize = DownloadStorageUsage.formatBytes(
                    downloads.downloadsByteSize(forFeed: feed)
                )
                if feedDownloadCount > 0 {
                    Text(
                        "Unsubscribe from \"\(feedDisplayTitle(feed))\"? Removes this podcast from Subscriptions, its feed settings and tags, queue items from this feed, and favorites, archive, playback history, bookmarks, and private notes for its episodes. This feed has \(feedDownloadCount) offline download(s) (\(feedDownloadSize)). Unsubscribe keeps those files; Unsubscribe and delete downloads removes only this feed’s offline files (incl. favorited). Does not clear other podcasts’ downloads or Delete all downloads."
                    )
                } else {
                    Text(
                        "Unsubscribe from \"\(feedDisplayTitle(feed))\"? Removes this podcast from Subscriptions, its feed settings and tags, queue items from this feed, and favorites, archive, playback history, bookmarks, and private notes for its episodes. Downloaded files are kept."
                    )
                }
            }
        }
    }

    /// Pasteboard copy of the **full** subscriptions library (not search/filters/UI sort/pin). Read-only.
    /// Distinct from OPML / HTML export (those omit local-folder feeds; this includes feed URLs honestly).
    private func copySubscriptions() {
        let text = subscriptionsPlainText
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        copiedAlertMessage = String(localized: "Subscriptions copied to the pasteboard.")
        copyFeedbackTick += 1
        showCopiedAlert = true
    }

    /// Push Feed detail for a pending `openFeed` deep link (player → Subscriptions).
    private func consumePendingFeedOpenIfNeeded() {
        guard let token = notificationDeepLink.feedOpenToken,
              token != lastHandledFeedOpenToken,
              let id = notificationDeepLink.pendingFeedId,
              let feed = store.feeds.first(where: { $0.id == id }) else { return }
        lastHandledFeedOpenToken = token
        // Defer so the Subscriptions tab is selected before push (same pattern as Settings Sync).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            path = NavigationPath()
            path.append(feed)
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

    /// Prefer search copy, then category, then language, then pinned, then tag — honest about which filter emptied the list.
    private var subscriptionsEmptyFilterMessage: String {
        if isSearchFiltering {
            return String(localized: "No subscriptions match your search.")
        }
        if isCategoryFiltering {
            return String(localized: "No subscriptions match this category filter.")
        }
        if isLanguageFiltering {
            return String(localized: "No subscriptions match this language filter.")
        }
        if tagFilter == .pinned {
            return String(localized: "No pinned podcasts")
        }
        return String(localized: "No subscriptions match this tag filter.")
    }

    /// VoiceOver context for the catalog-empty state versus a search/category/language/tag mismatch.
    /// The visible ContentUnavailableView copy stays concise; this value explains the next useful
    /// action without changing the subscription filtering semantics.
    private var subscriptionsEmptyStateAccessibilityValue: String {
        if store.feeds.isEmpty {
            return String(localized: "There are no subscriptions. Use Add podcast to subscribe, open Discover, choose a local folder, or import an OPML file.")
        }
        if isSearchFiltering {
            return String(localized: "No subscriptions match your search. Podcasts remain in the full subscriptions library. Refresh all, Copy, Share, and Unpin all still use the full library, not this empty view.")
        }
        if isCategoryFiltering {
            return String(localized: "No subscriptions match this category filter. Podcasts remain in the full subscriptions library. Refresh all, Copy, Share, and Unpin all still use the full library, not this empty view.")
        }
        if isLanguageFiltering {
            return String(localized: "No subscriptions match this language filter. Podcasts remain in the full subscriptions library. Refresh all, Copy, Share, and Unpin all still use the full library, not this empty view.")
        }
        if tagFilter == .pinned {
            return String(localized: "No pinned podcasts match the active filters. Podcasts remain in the full subscriptions library. Refresh all, Copy, Share, and Unpin all still use the full library, not this empty view.")
        }
        return String(localized: "No subscriptions match this tag filter. Podcasts remain in the full subscriptions library. Refresh all, Copy, Share, and Unpin all still use the full library, not this empty view.")
    }

    /// VoiceOver recovery hint for the search/category/language/tag mismatch empty state only.
    private var subscriptionsNoMatchAccessibilityHint: String {
        if isSearchFiltering {
            return String(localized: "Change or clear search to see other subscriptions. This does not unsubscribe or delete podcasts.")
        }
        if isCategoryFiltering {
            return String(localized: "Choose All or another category to see other subscriptions. This does not unsubscribe or delete podcasts.")
        }
        if isLanguageFiltering {
            return String(localized: "Choose All or another language to see other subscriptions. This does not unsubscribe or delete podcasts.")
        }
        if tagFilter == .pinned {
            return String(localized: "Choose All or change the search, category, or language filter to see other subscriptions. This does not unpin or unsubscribe.")
        }
        return String(localized: "Choose All or another tag to see other subscriptions. This does not unsubscribe or delete podcasts.")
    }

    /// VoiceOver for Subscriptions → Group by tag. Starts on for this visit
    /// only (not Settings, backup, or sync). On sections the All list by
    /// existing tags. Off is one flat Podcasts list. Hidden unless the tag
    /// chip is All. Not a filter and not a sort.
    private var groupByTagAccessibilityValue: String {
        if groupByTag {
            if store.allTags.isEmpty {
                return String(localized: "On. This starts on each time you open Subscriptions and is not saved. There are no tags, so the list stays one Podcasts section. No tag names are invented. Turning this on does not subscribe, unsubscribe, or download.")
            }
            return String(localized: "On. This starts on each time you open Subscriptions and is not saved. While the tag filter is All, podcasts are listed under each of their tags. A podcast with several tags appears in each of those sections. Podcasts with no tag appear under Untagged. Search, category, and language still narrow the list first. The unplayed remaining bar counts each podcast once. Turning this on does not change tags, sort, or Keep at top, and it does not subscribe, unsubscribe, or download.")
        }
        return String(localized: "Off. This is not how Subscriptions starts. The All list is one Podcasts section. Pinned podcasts still stay first. Tags are unchanged. Turning this off does not remove tags, unsubscribe, or download.")
    }

    private var groupByTagAccessibilityHint: String {
        String(localized: "Starts on for this visit only. Not saved in Settings or backup, and not synced. Shown only while the tag filter is All. Pinned, a named tag, and Untagged hide this toggle and stay a flat list. On groups by existing tags and does not hide podcasts. Off is one flat list. It does not rename tags or change sort.")
    }

    /// VoiceOver for the Subscriptions sort menu. Announces the saved choice.
    /// Recently updated is the default. Pinned stay first on every choice.
    /// Does not refresh, subscribe, unsubscribe, or download.
    private var subscriptionsSortAccessibilityValue: String {
        switch settings.subscriptionsSort {
        case .recentlyUpdated:
            return String(localized: "Recently updated. This is the default. Podcasts are ordered by the newest episode publish date. A podcast whose episodes have no date stays last. The display title breaks ties, using a custom title when one is set. Pinned podcasts stay above the others. Choosing this sort does not refresh feeds, subscribe, unsubscribe, or download.")
        case .alphabetical:
            return String(localized: "Alphabetical A–Z. This is not the default. Podcasts are ordered by display title, using a custom title when one is set, otherwise the feed title. Pinned podcasts stay above the others. Choosing this sort does not subscribe, unsubscribe, or download.")
        case .byAuthor:
            return String(localized: "Author A–Z. This is not the default. Podcasts are ordered by the author the feed provides. A podcast with no author stays last. No author is invented. The display title breaks ties. Pinned podcasts stay above the others. Choosing this sort does not subscribe, unsubscribe, or download.")
        case .byLanguage:
            return String(localized: "Language A–Z. This is not the default. Podcasts are ordered by the localized language name, or the raw language code when no localized name is available. A podcast with no language stays last. No language is invented. The display title breaks ties. Pinned podcasts stay above the others. Choosing this sort does not subscribe, unsubscribe, or download.")
        case .mostUnplayed:
            return String(localized: "Most unplayed. This is not the default. Podcasts with more unplayed episodes come first. Unplayed means not played and not archived, the same count as the subscription badge. Equal counts use the display title. This uses each podcast’s stored episodes, not the All Episodes newest-500 cap. Pinned podcasts stay above the others. Choosing this sort does not mark episodes played, subscribe, unsubscribe, or download.")
        case .recentlyRefreshed:
            return String(localized: "Recently refreshed. This is not the default. Podcasts with a newer successful network refresh come first. A podcast that has never refreshed successfully stays last, including a local folder. No refresh time is invented. The display title breaks ties. Pinned podcasts stay above the others. Choosing this sort does not refresh feeds, subscribe, unsubscribe, or download.")
        case .leastRecentlyRefreshed:
            return String(localized: "Least recently refreshed. This is not the default. Podcasts with an older successful network refresh come first. A podcast that has never refreshed successfully stays last, including a local folder. No refresh time is invented. The display title breaks ties. Pinned podcasts stay above the others. Choosing this sort does not refresh feeds, subscribe, unsubscribe, or download.")
        }
    }

    private var subscriptionsSortAccessibilityHint: String {
        String(localized: "Saved on this device and included in Settings backup. Not synced. Applied after search, category, language, and tag filters, including the Pinned chip. Group by tag keeps this order inside each section. Keep at top stays first and is not its own sort choice. There is no drag reorder of subscriptions. It does not change filters, tags, or pins.")
    }

    /// VoiceOver hint for tag-row chips (Pinned vs tag / Untagged / All).
    private func chipAccessibilityHint(_ chip: SubscriptionTagFilter) -> String {
        switch chip {
        case .pinned:
            return String(localized: "Filters the Subscriptions list to pinned podcasts")
        default:
            return String(localized: "Filters the Subscriptions list by tag")
        }
    }

    /// If Pinned is selected and the last Keep-at-top feed was unpinned/removed, fall back to All.
    private func resetPinnedFilterIfNeeded() {
        if tagFilter == .pinned, !hasAnyPinnedSubscription {
            tagFilter = .all
        }
    }

    @ViewBuilder
    private func feedRow(_ feed: PodcastFeed, summary: FeedUnplayedRemainingSummary?) -> some View {
        let unplayed = summary?.unplayedCount ?? 0
        let remainingLabel = feedRowRemainingLabel(summary)
        NavigationLink(value: feed) {
            HStack(alignment: .center, spacing: 12) {
                if LocalFolderFeed.isLocalFolderFeed(feed) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(feedDisplayTitle(feed))
                            .font(.headline)
                        if LocalFolderFeed.isLocalFolderFeed(feed) {
                            Text("Folder")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2), in: Capsule())
                                .foregroundStyle(.orange)
                                .accessibilityHidden(true)
                        }
                        // Channel itunes:explicit — hide when feed does not mark it (never invent).
                        if feed.isExplicit {
                            Text(String(localized: "Explicit"))
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.2), in: Capsule())
                                .accessibilityHidden(true)
                        }
                        // Channel podcast:medium raw string when set — hide when missing (never invent/remap).
                        if let medium = feed.displayMedium {
                            Text(medium)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.2), in: Capsule())
                                .accessibilityHidden(true)
                        }
                        // Channel itunes:type when set — Episodic/Serial or raw; hide when missing (never invent; capsule display-only; Serial nil-only Oldest-first is in PodcastStore).
                        if let itunesType = feed.displayItunesType {
                            Text(itunesType)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.2), in: Capsule())
                                .accessibilityHidden(true)
                        }
                        // Channel podcast:updateFrequency when set — free-form text or Complete; hide when missing (never invent; display-only).
                        if let uf = feed.displayUpdateFrequency {
                            FeedUpdateFrequencyCapsule(frequency: uf, compact: true)
                                .accessibilityHidden(true)
                        }
                        // Channel itunes:complete — hide when false (never invent; display-only; distinct from updateFrequency complete).
                        if feed.isItunesComplete {
                            Text(String(localized: "Complete"))
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.2), in: Capsule())
                                .accessibilityHidden(true)
                        }
                    }
                    // Feed author when present (itunes:author / Atom name / managingEditor); hide when missing.
                    if let author = feed.displayAuthor {
                        Text(author)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .accessibilityHidden(true)
                    }
                    // Feed language when present (localized name or raw code); hide when missing.
                    if let language = feed.displayLanguage {
                        Text(language)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .accessibilityHidden(true)
                    }
                    // itunes:category caption when present; hide when none — never invent.
                    if let cats = feed.categoriesCaption {
                        Text(cats)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .accessibilityHidden(true)
                    }
                    // Last refreshed: subtle caption only when row is not already crowded (no author/language/categories).
                    // Local-folder / nil hide. Prefer Feed detail + VoiceOver when space is tight.
                    if feed.displayAuthor == nil,
                       feed.displayLanguage == nil,
                       feed.categoriesCaption == nil,
                       !LocalFolderFeed.isLocalFolderFeed(feed),
                       let date = feed.lastRefreshedAt {
                        Text(date, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .accessibilityHidden(true)
                    }
                    HStack(spacing: 6) {
                        Text("\(feed.episodes.count) episodes")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        let tags = store.tags(for: feed.id)
                        if !tags.isEmpty, tagFilter == .all, !groupByTag {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(tags.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 8)
                // Subtle Keep-at-top pin (does not replace unplayed badge).
                if store.isPinned(feedId: feed.id) {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                // AntennaPod-like unplayed badge + per-feed remaining; both hidden when 0 unplayed.
                // Remaining text also hidden when all durations unknown (badge still shows count).
                VStack(alignment: .trailing, spacing: 4) {
                    if unplayed > 0 {
                        Text("\(unplayed)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, unplayed >= 10 ? 7 : 0)
                            .frame(minWidth: 22, minHeight: 22)
                            .background(Color.accentColor, in: Capsule())
                            .accessibilityHidden(true)
                    }
                    if let remainingLabel {
                        Text(remainingLabel)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(subscriptionRowAccessibilityLabel(
                feed: feed,
                unplayed: unplayed,
                remainingLabel: remainingLabel
            ))
            .modifier(AccessibilityHintIfPresent(hint: feedRowRemainingAccessibilityHint(shown: remainingLabel != nil)))
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                feedPendingUnsubscribe = feed
            } label: {
                Label("Unsubscribe", systemImage: "trash")
            }
            .accessibilityHint(String(localized: "Asks for confirmation, then removes this podcast from Subscriptions, its feed settings and tags, queue items from this feed, and favorites, archive, playback history, bookmarks, and private notes for its episodes. When this feed has offline downloads, you can keep them or delete only this feed’s files including favorites. Does not clear other podcasts’ downloads."))
        }
        .swipeActions(edge: .leading) {
            Button {
                store.togglePinned(feedId: feed.id)
            } label: {
                if store.isPinned(feedId: feed.id) {
                    Label("Don’t keep at top", systemImage: "pin.slash")
                } else {
                    Label("Keep at top", systemImage: "pin")
                }
            }
            .tint(.orange)
            .accessibilityLabel(
                store.isPinned(feedId: feed.id)
                    ? String(localized: "Don’t keep at top")
                    : String(localized: "Keep at top")
            )
            .accessibilityHint(String(localized: "Pins or unpins this podcast above unpinned ones on Subscriptions for every sort (Recently updated, Alphabetical, and others). Not a separate sort mode. Local preference only — not synced to gpodder. Included in iOS JSON backup with other feed settings. Cleared when you unsubscribe. Does not unsubscribe, change tags, or change the Subscriptions sort preference. Toggles immediately. No confirmation."))
            Button {
                Task { await store.refresh(feed) }
            } label: {
                if LocalFolderFeed.isLocalFolderFeed(feed) {
                    Label("Rescan folder", systemImage: "arrow.clockwise")
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .tint(.blue)
            .accessibilityHint(
                LocalFolderFeed.isLocalFolderFeed(feed)
                    ? String(localized: "Re-reads audio files in the folder via the saved bookmark. Does not fetch an RSS feed or invent network episodes. Distinct from Refresh for subscribed RSS podcasts. Does not change Keep updated or start Auto-download.")
                    : String(localized: "Fetches this podcast’s feed from the network, including when Keep updated is Never. Not Refresh all. Feed refresh is not limited by the Wi‑Fi-only toggles and may use cellular. Does not invent episodes; Auto-download may enqueue newly appeared ones after a successful refresh. Distinct from Rescan folder for local-folder podcasts.")
            )
        }
        .modifier(SubscriptionRowContextMenu(
            feedId: feed.id,
            podcastTitle: EpisodeCopyLinks.trimmedFeedTitle(feedDisplayTitle(feed)),
            websiteURL: feed.websiteURL,
            isPinned: store.isPinned(feedId: feed.id),
            openURL: openURL,
            onTogglePin: { store.togglePinned(feedId: feed.id) },
            onCopyPodcastTitle: { title in
                copiedAlertMessage = EpisodeCopyLinks.copyPodcastTitle(title)
                copyFeedbackTick += 1
                showCopiedAlert = true
            }
        ))
    }


    /// VoiceOver for last successful network refresh. Nil for local-folder / never refreshed (never invent).
    private func lastRefreshedAccessibility(_ feed: PodcastFeed) -> String? {
        guard !LocalFolderFeed.isLocalFolderFeed(feed),
              let date = feed.lastRefreshedAt else { return nil }
        let caption = date.formatted(date: .abbreviated, time: .shortened)
        return String(localized: "Last refreshed \(caption)")
    }

    /// Compact per-feed remaining for a subscription row. Hidden when unplayed is 0 or all
    /// durations unknown (no invented time). Prefix `~` when any unplayed episode lacks duration.
    private func feedRowRemainingLabel(_ summary: FeedUnplayedRemainingSummary?) -> String? {
        guard let summary, summary.unplayedCount > 0 else { return nil }
        return EpisodeRemainingTime.timeLeftLabel(
            remainingSeconds: summary.remainingSeconds,
            knownCount: summary.knownCount,
            unknownCount: summary.unknownCount
        )
    }

    /// VoiceOver hint for the per-feed remaining caption only. Nil when that caption is
    /// hidden. The visible time string is unchanged. Speed off = wall-clock. Speed on =
    /// estimate ÷ this podcast’s speed or Default speed (never below 0.5), not the live
    /// session rate and not Volume boost. Scope is this podcast’s unplayed stored episodes,
    /// not the Subscriptions list bar, Group by tag, or a Home preview.
    private func feedRowRemainingAccessibilityHint(shown: Bool) -> String? {
        guard shown else { return nil }
        if settings.remainingTimeRespectsSpeed {
            return String(localized: "Estimate. Remaining time respects speed is on, so each of this podcast’s unplayed stored episodes is divided by this podcast’s playback speed, or Default speed, never below 0.5. This is not the live session rate and not Volume boost. This caption is only this podcast’s unplayed stored episodes, not the Subscriptions list bar, not Group by tag, and not a Home preview. Unplayed means not played and not archived, over this podcast’s stored episodes, not the All Episodes newest-500 cap. Unknown durations are left out and no time is invented. The episode that is playing uses the live position, but the divisor stays this podcast’s speed or Default speed. It does not play, download, or mark episodes played.")
        }
        return String(localized: "Wall-clock remaining. Remaining time respects speed is off, so playback speed does not change this caption. This caption is only this podcast’s unplayed stored episodes, not the Subscriptions list bar, not Group by tag, and not a Home preview. Unplayed means not played and not archived, over this podcast’s stored episodes, not the All Episodes newest-500 cap. Unknown durations are left out and no time is invented. The episode that is playing uses the live position. It does not play, download, or mark episodes played.")
    }

    private func unplayedCountLabel(_ count: Int) -> String {
        if count == 1 {
            return String(localized: "1 unplayed")
        }
        return String(localized: "\(count) unplayed")
    }

    private func subscriptionRowAccessibilityLabel(
        feed: PodcastFeed,
        unplayed: Int,
        remainingLabel: String?
    ) -> String {
        var parts: [String] = [feedDisplayTitle(feed)]
        if store.isPinned(feedId: feed.id) {
            parts.append(String(localized: "Kept at top"))
        }
        if LocalFolderFeed.isLocalFolderFeed(feed) {
            parts.append(String(localized: "Folder"))
        }
        if feed.isExplicit {
            parts.append(String(localized: "Explicit"))
        }
        if let medium = feed.displayMedium {
            parts.append(String(localized: "Medium \(medium)"))
        }
        if let a11y = feed.itunesTypeAccessibilityLabel {
            parts.append(a11y)
        }
        if let uf = feed.displayUpdateFrequency {
            parts.append(uf.accessibilityLabel)
        }
        if feed.isItunesComplete {
            parts.append(feed.itunesCompleteAccessibilityLabel)
        }
        if let author = feed.displayAuthor {
            parts.append(author)
        }
        if let language = feed.displayLanguage {
            parts.append(String(localized: "Language \(language)"))
        }
        if let cats = feed.categoriesCaption {
            parts.append(String(localized: "Categories \(cats)"))
        }
        let epCount = feed.episodes.count
        if epCount == 1 {
            parts.append(String(localized: "1 episode"))
        } else {
            parts.append(String(localized: "\(epCount) episodes"))
        }
        if unplayed > 0 {
            parts.append(unplayedCountLabel(unplayed))
        }
        if let remainingLabel {
            parts.append(remainingLabel)
        }
        if let lastRefreshed = lastRefreshedAccessibility(feed) {
            parts.append(lastRefreshed)
        }
        let tags = store.tags(for: feed.id)
        if !tags.isEmpty, tagFilter == .all, !groupByTag {
            parts.append(tags.joined(separator: ", "))
        }
        return parts.joined(separator: ", ")
    }
}


/// Applies a VoiceOver hint only when one is present (rows without a remaining caption stay unchanged).
private struct AccessibilityHintIfPresent: ViewModifier {
    let hint: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let hint, !hint.isEmpty {
            content.accessibilityHint(hint)
        } else {
            content
        }
    }
}

/// Subscriptions row context menu: Keep at top toggle + optional Open podcast website.
private struct SubscriptionRowContextMenu: ViewModifier {
    let feedId: UUID
    let podcastTitle: String?
    let websiteURL: URL?
    let isPinned: Bool
    let openURL: OpenURLAction
    let onTogglePin: () -> Void
    let onCopyPodcastTitle: (String) -> Void

    func body(content: Content) -> some View {
        content.contextMenu {
            Button {
                onTogglePin()
            } label: {
                if isPinned {
                    Label("Don’t keep at top", systemImage: "pin.slash")
                } else {
                    Label("Keep at top", systemImage: "pin")
                }
            }
            .accessibilityLabel(
                isPinned
                    ? String(localized: "Don’t keep at top")
                    : String(localized: "Keep at top")
            )
            .accessibilityHint(String(localized: "Pins or unpins this podcast above unpinned ones on Subscriptions for every sort (Recently updated, Alphabetical, and others). Not a separate sort mode. Local preference only — not synced to gpodder. Included in iOS JSON backup with other feed settings. Cleared when you unsubscribe. Does not unsubscribe, change tags, or change the Subscriptions sort preference. Toggles immediately. No confirmation."))

            if let podcastTitle {
                Button {
                    onCopyPodcastTitle(podcastTitle)
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

            if let url = websiteURL {
                Button {
                    openURL(url)
                } label: {
                    Label("Open podcast website", systemImage: "safari")
                }
                .accessibilityLabel(String(localized: "Open podcast website"))
                .accessibilityHint(String(localized: "Opens the feed-provided podcast website http(s) link in the system browser — not an in-app WebView. No confirmation. Never uses the feed RSS URL or an episode webpage. Distinct from Open episode website, Copy podcast website, and Share podcast website. Does not subscribe, download, or change playback."))
            }
        }
    }
}

private struct TagFilterChip: View {
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
