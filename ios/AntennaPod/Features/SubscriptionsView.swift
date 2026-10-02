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
    private var subscriptionsRemainingInfoLabel: String? {
        EpisodeRemainingTime.unplayedInfoBarLabel(for: subscriptionsRemainingSummary)
    }

    private var subscriptionsRemainingAccessibilityLabel: String {
        guard let label = subscriptionsRemainingInfoLabel else { return "" }
        var parts = [String(localized: "Subscriptions unplayed remaining time \(label)")]
        let unknown = subscriptionsRemainingSummary.unknownCount
        if unknown > 0 {
            parts.append(String(localized: "Remaining time excludes \(unknown) episode(s) with unknown duration"))
        }
        if isSearchFiltering || isCategoryFiltering || isLanguageFiltering || tagFilter != .all {
            parts.append(String(localized: "Subscriptions remaining time covers visible podcasts only (search, tag, category, or language filter), not the full library"))
        }
        return parts.joined(separator: ". ")
    }

    private var subscriptionsRemainingSummary: EpisodeRemainingTime.Summary {
        var episodeCount = 0
        var remaining = 0.0
        var known = 0
        var unknown = 0
        for feed in tagFilteredFeeds {
            guard let s = unplayedRemainingByFeedId[feed.id] else { continue }
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

    var body: some View {
        NavigationStack(path: $path) {
            List {
                // AntennaPod-like subscriptions info bar (unplayed remaining over visible feeds).
                // Per-feed remaining also on each row (same map); unique feeds when grouped by tag.
                if let remainingLabel = subscriptionsRemainingInfoLabel {
                    Section {
                        Text(remainingLabel)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(subscriptionsRemainingAccessibilityLabel)
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
                } else {
                    ForEach(groupedSections, id: \.title) { section in
                        Section(section.title) {
                            ForEach(section.feeds) { feed in
                                feedRow(feed)
                            }
                        }
                    }
                }
            }
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
            .toolbar {
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
                        parental.needsPINForAddDiscover ? "Add podcast (PIN required)" : "Add podcast"
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
                    .accessibilityHint(String(localized: "Rename or delete subscription tags across all podcasts"))
                }
            }
            .sheet(isPresented: $showAdd) {
                AddFeedView()
            }
            .navigationDestination(isPresented: $navigateToDiscover) {
                TopListsView()
            }
            .sheet(isPresented: $showAddPINGate) {
                ParentalPINPromptSheet(
                    title: "Parental controls",
                    message: "Enter your PIN to add or discover podcasts.",
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
                    title: "Parental controls",
                    message: "Enter your PIN to open Discover.",
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
                        "Unsubscribe from \"\(feedDisplayTitle(feed))\"? Removes this podcast from Subscriptions, its feed settings and tags, queue items from this feed, and favorites, archive, and playback history for its episodes. This feed has \(feedDownloadCount) offline download(s) (\(feedDownloadSize)). Unsubscribe keeps those files; Unsubscribe and delete downloads removes only this feed’s offline files (incl. favorited). Does not clear other podcasts’ downloads or Delete all downloads."
                    )
                } else {
                    Text(
                        "Unsubscribe from \"\(feedDisplayTitle(feed))\"? Removes this podcast from Subscriptions, its feed settings and tags, queue items from this feed, and favorites, archive, and playback history for its episodes. Downloaded files are kept."
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
            return String(localized: "No subscriptions match your search. Clear or change the search to see your podcasts.")
        }
        if isCategoryFiltering {
            return String(localized: "No subscriptions match this category filter. Choose All or another category.")
        }
        if isLanguageFiltering {
            return String(localized: "No subscriptions match this language filter. Choose All or another language.")
        }
        if tagFilter == .pinned {
            return String(localized: "No pinned podcasts match the active filters. Choose All or change the search, category, or language filter.")
        }
        return String(localized: "No subscriptions match this tag filter. Choose All or another tag.")
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
    private func feedRow(_ feed: PodcastFeed) -> some View {
        let summary = unplayedRemainingByFeedId[feed.id]
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
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                feedPendingUnsubscribe = feed
            } label: {
                Label("Unsubscribe", systemImage: "trash")
            }
            .accessibilityHint(String(localized: "Opens unsubscribe confirmation; optional delete this feed’s downloads"))
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
            .accessibilityHint(String(localized: "Pins or unpins this podcast at the top of the Subscriptions list"))
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
                    ? String(localized: "Re-reads audio files in the folder. Does not fetch an RSS feed.")
                    : String(localized: "Fetches the podcast feed from the network")
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
            .accessibilityHint(String(localized: "Pins or unpins this podcast at the top of the Subscriptions list"))

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
                .accessibilityHint(String(localized: "Opens the podcast webpage in the system browser"))
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
