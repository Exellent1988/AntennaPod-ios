import SwiftUI

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

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    /// Client-side list order after search/category/language/tag filters (no drag-reorder of subscriptions).
    /// Author / language: A–Z by feed-provided `displayAuthor` / `displayLanguage`; missing values last; title tiebreak.
    /// Most unplayed: descending per-feed unplayed count (`!isPlayed && !isArchived`, same as badges /
    /// Inbox / `unplayedCountsByFeedId`); equal counts → title A–Z tiebreak.
    private func sortedFeeds(_ feeds: [PodcastFeed]) -> [PodcastFeed] {
        switch settings.subscriptionsSort {
        case .recentlyUpdated:
            return feeds.sorted { lhs, rhs in
                let l = lhs.episodes.compactMap(\.pubDateEpochMs).max() ?? Int64.min
                let r = rhs.episodes.compactMap(\.pubDateEpochMs).max() ?? Int64.min
                if l != r { return l > r }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        case .alphabetical:
            return feeds.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        case .byAuthor:
            return feeds.sorted { lhs, rhs in
                switch (lhs.displayAuthor, rhs.displayAuthor) {
                case (nil, nil):
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                case (nil, _):
                    return false
                case (_, nil):
                    return true
                case let (l?, r?):
                    let cmp = l.localizedCaseInsensitiveCompare(r)
                    if cmp != .orderedSame { return cmp == .orderedAscending }
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
            }
        case .byLanguage:
            return feeds.sorted { lhs, rhs in
                switch (lhs.displayLanguage, rhs.displayLanguage) {
                case (nil, nil):
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                case (nil, _):
                    return false
                case (_, nil):
                    return true
                case let (l?, r?):
                    let cmp = l.localizedCaseInsensitiveCompare(r)
                    if cmp != .orderedSame { return cmp == .orderedAscending }
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
            }
        case .mostUnplayed:
            // Same definition as row badges / Inbox (`!isPlayed && !isArchived`; missing = 0).
            let counts = store.unplayedCountsByFeedId()
            return feeds.sorted { lhs, rhs in
                let l = counts[lhs.id] ?? 0
                let r = counts[rhs.id] ?? 0
                if l != r { return l > r }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }

    /// Visible subscriptions after search; empty query shows full list under current sort.
    /// Matches feed **title**, optional **descriptionText**, optional **author**, optional **language**,
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

    /// Search → category → language → tag (AND). Remaining-time / unplayed bars use this visible set.
    private var tagFilteredFeeds: [PodcastFeed] {
        let base = languageFilteredFeeds
        switch tagFilter {
        case .all:
            return base
        case .untagged:
            return base.filter { store.tags(for: $0.id).isEmpty }
        case .tag(let name):
            return base.filter { feed in
                store.tags(for: feed.id).contains(where: { FeedTags.equal($0, name) })
            }
        }
    }

    /// Sections when grouping is on and filter is All (multi-tag feeds appear under each tag).
    /// Feeds within each section follow `subscriptionsSort` (inherited from `languageFilteredFeeds`).
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

    private var filterChips: [SubscriptionTagFilter] {
        var chips: [SubscriptionTagFilter] = [.all]
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
        return store.unplayedRemainingByFeedId()
    }

    /// AntennaPod-like info bar: unplayed count + remaining over unplayed episodes of
    /// **visible** subscriptions (search + category + language + tag). Built by summing per-feed summaries from
    /// `unplayedRemainingByFeedId` over **unique** `tagFilteredFeeds` (multi-tag Group by tag
    /// does not double-count). Same `!isPlayed && !isArchived` definition as per-row badges /
    /// Inbox / per-feed row remaining. Full stored feed catalogs — **not** the All Episodes
    /// newest-500 soft cap. Remaining per episode = `max(0, duration − position)` when
    /// duration known; **unknown duration skipped** (tilde when any skipped); live player
    /// when current. Wall-clock only (no playback-speed divide). Distinct from Inbox tab
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

                if !store.feeds.isEmpty, !store.allTags.isEmpty || tagFilter != .all {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(filterChips) { chip in
                                    TagFilterChip(
                                        title: chip.label,
                                        selected: tagFilter == chip,
                                        accessibilityHint: String(localized: "Filters the Subscriptions list by tag")
                                    ) {
                                        tagFilter = chip
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

                        if tagFilter == .all {
                            Toggle("Group by tag", isOn: $groupByTag)
                        }
                    } header: {
                        Text("Tags")
                    }
                }

                if store.feeds.isEmpty {
                    ContentUnavailableView(
                        "No subscriptions",
                        systemImage: "dot.radiowaves.left.and.right",
                        description: Text("Search Apple Podcasts, open Discover for charts, add by feed URL, pick a local Folder, or import an OPML file.")
                    )
                } else if tagFilteredFeeds.isEmpty {
                    ContentUnavailableView(
                        "No matching podcasts",
                        systemImage: "magnifyingglass",
                        description: Text(subscriptionsEmptyFilterMessage)
                    )
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
            }
            .onAppear {
                consumePendingFeedOpenIfNeeded()
            }
            .onChange(of: notificationDeepLink.feedOpenToken) { _, _ in
                consumePendingFeedOpenIfNeeded()
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
                        "Unsubscribe from \"\(feed.title)\"? Removes this podcast from Subscriptions, its feed settings and tags, queue items from this feed, and favorites, archive, and playback history for its episodes. This feed has \(feedDownloadCount) offline download(s) (\(feedDownloadSize)). Unsubscribe keeps those files; Unsubscribe and delete downloads removes only this feed’s offline files (incl. favorited). Does not clear other podcasts’ downloads or Clear all downloads."
                    )
                } else {
                    Text(
                        "Unsubscribe from \"\(feed.title)\"? Removes this podcast from Subscriptions, its feed settings and tags, queue items from this feed, and favorites, archive, and playback history for its episodes. Downloaded files are kept."
                    )
                }
            }
        }
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

    /// Prefer search copy, then category, then language, then tag — honest about which filter emptied the list.
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
        return String(localized: "No subscriptions match this tag filter.")
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
                        Text(feed.title)
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
                        // Channel itunes:type when set — Episodic/Serial or raw; hide when missing (never invent; display-only).
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
                Task { await store.refresh(feed) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .tint(.blue)
        }
        .modifier(OpenPodcastWebsiteContextMenu(url: feed.websiteURL, openURL: openURL))
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
        var parts: [String] = [feed.title]
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
        let tags = store.tags(for: feed.id)
        if !tags.isEmpty, tagFilter == .all, !groupByTag {
            parts.append(tags.joined(separator: ", "))
        }
        return parts.joined(separator: ", ")
    }
}


/// Attaches a context-menu action only when `siteLink` is a usable http(s) URL (hidden otherwise).
private struct OpenPodcastWebsiteContextMenu: ViewModifier {
    let url: URL?
    let openURL: OpenURLAction

    @ViewBuilder
    func body(content: Content) -> some View {
        if let url {
            content.contextMenu {
                Button {
                    openURL(url)
                } label: {
                    Label("Open podcast website", systemImage: "safari")
                }
                .accessibilityLabel(String(localized: "Open podcast website"))
                .accessibilityHint(String(localized: "Opens the podcast webpage in the system browser"))
            }
        } else {
            content
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
