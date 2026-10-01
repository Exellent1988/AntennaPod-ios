import SwiftUI

/// Landing tab: honest previews driven by Settings → Home layout (order + visibility).
/// `.searchable` filters visible section episode/podcast previews (title + feed); empty sections hide while filtering.
struct HomeView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var parental: ParentalControls
    @Binding var selectedTab: RootTab
    @State private var showDiscoverPINGate = false
    @State private var navigateToDiscover = false
    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?

    private let previewLimit = 5
    private let feedsLimit = 5
    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    private var isSearchFiltering: Bool {
        !debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Continue preview: filter full continue catalog by title/feed, then cap (matches while searching beyond first 5).
    private var continueItems: [HistoryEpisode] {
        Array(filterEpisodes(store.continueListeningEpisodes).prefix(previewLimit))
    }

    private var inboxItems: [InboxEpisode] {
        Array(filterEpisodes(store.inboxEpisodes).prefix(previewLimit))
    }

    private var queueItems: [PodcastEpisode] {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = store.queue
        let filtered: [PodcastEpisode]
        if q.isEmpty {
            filtered = base
        } else {
            filtered = base.filter { episode in
                if episode.title.localizedCaseInsensitiveContains(q) { return true }
                let feedTitle = store.feed(containingEpisodeId: episode.id)?.title ?? ""
                return feedTitle.localizedCaseInsensitiveContains(q)
            }
        }
        return Array(filtered.prefix(previewLimit))
    }

    private var recentFeeds: [PodcastFeed] {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = store.recentlyUpdatedFeeds
        let filtered: [PodcastFeed]
        if q.isEmpty {
            filtered = base
        } else {
            filtered = base.filter { $0.title.localizedCaseInsensitiveContains(q) }
        }
        return Array(filtered.prefix(feedsLimit))
    }

    private var favoriteItems: [FavoriteEpisode] {
        Array(filterEpisodes(store.favoriteEpisodes).prefix(previewLimit))
    }

    /// AntennaPod-like info bar: episode count + remaining over the **visible Continue preview**
    /// rows only (`continueItems` = filter then soft-cap `previewLimit`). Remaining per episode =
    /// `max(0, duration − position)` when duration known; unplayed with duration contributes full
    /// duration; **played** (not current) → 0 (Continue catalog is already in-progress-only —
    /// still handled for honesty); **unknown duration skipped** (tilde when any skipped).
    /// Currently playing uses live `PlaybackService` position/duration. Wall-clock only (no
    /// playback-speed divide).
    /// **Preview soft-cap honesty:** never claims remaining beyond the visible preview rows
    /// (first `previewLimit` after search filter) — not the full `continueListeningEpisodes`
    /// catalog / History list.
    private var continueRemainingInfoLabel: String? {
        guard !continueItems.isEmpty else { return nil }
        let summary = continueRemainingSummary
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

    private var continueRemainingAccessibilityLabel: String {
        guard let label = continueRemainingInfoLabel else { return "" }
        var parts = [String(localized: "Continue listening remaining time \(label)")]
        let unknown = continueRemainingSummary.unknownCount
        if unknown > 0 {
            parts.append(String(localized: "Remaining time excludes \(unknown) episode(s) with unknown duration"))
        }
        // Soft-cap: filtered continue catalog longer than visible preview rows.
        let filteredCatalogCount = filterEpisodes(store.continueListeningEpisodes).count
        if filteredCatalogCount > continueItems.count {
            parts.append(
                String(
                    localized: "Home Continue remaining time covers the preview only (first \(previewLimit)), not the full continue catalog"
                )
            )
        }
        return parts.joined(separator: ". ")
    }

    private var continueRemainingSummary: ContinueRemainingSummary {
        var remaining = 0.0
        var known = 0
        var unknown = 0
        for item in continueItems {
            let episode = item.episode
            guard let duration = knownDurationSeconds(for: episode) else {
                unknown += 1
                continue
            }
            known += 1
            // Mark-played clears position; do not count full duration as still left
            // (unless this is the live current episode — use live position instead).
            // Continue catalog is in-progress-only; played→0 still kept for computation honesty.
            if store.isPlayed(episode.id), playback.currentEpisode?.id != episode.id {
                continue
            }
            let position = positionSeconds(for: episode)
            remaining += max(0, duration - position)
        }
        return ContinueRemainingSummary(
            episodeCount: continueItems.count,
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

    /// Library content that would appear under visible non-Discover sections (respects search filter).
    private var hasVisibleLibraryContent: Bool {
        for id in settings.visibleHomeSections {
            switch id {
            case .continueListening:
                if !continueItems.isEmpty { return true }
            case .inbox:
                if !inboxItems.isEmpty { return true }
            case .queue:
                if !queueItems.isEmpty { return true }
            case .recentlyUpdated:
                if !recentFeeds.isEmpty { return true }
            case .favorites:
                if !favoriteItems.isEmpty { return true }
            case .discover:
                continue
            }
        }
        return false
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(settings.visibleHomeSections) { sectionId in
                    homeSection(for: sectionId)
                }

                if isSearchFiltering && !hasVisibleLibraryContent {
                    ContentUnavailableView(
                        "No matching home items",
                        systemImage: "magnifyingglass",
                        description: Text("No episodes or podcasts on Home match your search.")
                    )
                } else if !isSearchFiltering && !hasVisibleLibraryContent {
                    ContentUnavailableView(
                        "Welcome",
                        systemImage: "house",
                        description: Text(welcomeDescription)
                    )
                }
            }
            .navigationTitle("Home")
            .searchable(text: $searchText, prompt: "Search home")
            .onChange(of: searchText) { _, newValue in
                scheduleFilter(for: newValue)
            }
            .onDisappear {
                debounceTask?.cancel()
            }
            .navigationDestination(for: PodcastFeed.self) { feed in
                FeedDetailView(feed: feed)
            }
            .navigationDestination(isPresented: $navigateToDiscover) {
                TopListsView()
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
            .refreshable {
                await store.refreshAllFeeds()
            }
            .overlay {
                if store.isLoading {
                    ProgressView("Refreshing feeds…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let error = store.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(.ultraThinMaterial)
                }
            }
        }
    }

    private var welcomeDescription: String {
        if settings.isHomeSectionVisible(.discover) {
            return String(localized: "Subscribe to podcasts to see continue listening, new episodes, your queue, and recently updated feeds here. Or use Discover for Apple Charts. Customize sections under Settings → Home layout.")
        }
        return String(localized: "Subscribe to podcasts to see continue listening, new episodes, your queue, and recently updated feeds here. Customize sections under Settings → Home layout.")
    }

    @ViewBuilder
    private func homeSection(for id: HomeSectionId) -> some View {
        switch id {
        case .discover:
            // Charts preview is not title-filtered; hide while searching so empty state can show.
            if !isSearchFiltering {
                discoverSection
            }
        case .continueListening:
            if !continueItems.isEmpty {
                continueSection
            }
        case .inbox:
            if !inboxItems.isEmpty {
                inboxSection
            }
        case .queue:
            if !queueItems.isEmpty {
                queueSection
            }
        case .recentlyUpdated:
            if !recentFeeds.isEmpty {
                recentlyUpdatedSection
            }
        case .favorites:
            if !favoriteItems.isEmpty {
                favoritesSection
            }
        }
    }

    @ViewBuilder
    private var discoverSection: some View {
        Section {
            HomeTopListsPreview()
        } header: {
            sectionHeader("Discover", systemImage: "chart.bar")
        } footer: {
            Button {
                if parental.needsPINForAddDiscover {
                    showDiscoverPINGate = true
                } else {
                    navigateToDiscover = true
                }
            } label: {
                HStack(spacing: 4) {
                    Text("See all charts")
                        .font(.footnote)
                    if parental.needsPINForAddDiscover {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var continueSection: some View {
        Section {
            // AntennaPod-like Continue preview info bar (visible preview rows remaining time).
            // Soft-cap honesty: first `previewLimit` after search filter — not full continue catalog.
            if let remainingLabel = continueRemainingInfoLabel {
                Text(remainingLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(continueRemainingAccessibilityLabel)
                    .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
            }
            ForEach(continueItems) { item in
                EpisodeRow(
                    episode: item.episode,
                    feedTitle: item.feedTitle,
                    dateOverride: Date(timeIntervalSince1970: Double(item.lastPlayedAtEpochMs) / 1000),
                    dateAccessibilityLabel: "Last played"
                )
            }
        } header: {
            sectionHeader("Continue listening", systemImage: "play.circle")
        } footer: {
            NavigationLink {
                HistoryView()
            } label: {
                Text(store.continueListeningEpisodes.count > previewLimit ? "See all in History" : "Open History")
                    .font(.footnote)
            }
        }
    }

    @ViewBuilder
    private var inboxSection: some View {
        Section {
            ForEach(inboxItems) { item in
                EpisodeRow(episode: item.episode, feedTitle: item.feedTitle)
            }
        } header: {
            homeSectionLink(
                title: "New / Inbox",
                systemImage: "tray.fill",
                tab: .inbox,
                total: store.inboxEpisodes.count
            )
        } footer: {
            if store.inboxEpisodes.count > previewLimit {
                Button("See all in Inbox") {
                    selectedTab = .inbox
                }
                .font(.footnote)
            }
        }
    }

    @ViewBuilder
    private var queueSection: some View {
        Section {
            ForEach(queueItems) { episode in
                EpisodeRow(
                    episode: episode,
                    feedTitle: store.feed(containingEpisodeId: episode.id)?.title ?? ""
                )
            }
        } header: {
            homeSectionLink(
                title: "Queue",
                systemImage: "list.bullet",
                tab: .queue,
                total: store.queue.count
            )
        } footer: {
            if store.queue.count > previewLimit {
                Button("See all in Queue") {
                    selectedTab = .queue
                }
                .font(.footnote)
            }
        }
    }

    @ViewBuilder
    private var recentlyUpdatedSection: some View {
        Section {
            ForEach(recentFeeds) { feed in
                NavigationLink(value: feed) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(feed.title)
                            .font(.headline)
                        HStack(spacing: 8) {
                            Text("\(feed.episodes.count) episodes")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let ms = feed.episodes.compactMap(\.pubDateEpochMs).max() {
                                Text(Date(timeIntervalSince1970: Double(ms) / 1000), style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("Newest episode")
                            }
                        }
                    }
                }
            }
        } header: {
            sectionHeader("Recently updated", systemImage: "dot.radiowaves.left.and.right")
        } footer: {
            Button("See all subscriptions") {
                selectedTab = .subscriptions
            }
            .font(.footnote)
        }
    }

    @ViewBuilder
    private var favoritesSection: some View {
        Section {
            ForEach(favoriteItems) { item in
                EpisodeRow(
                    episode: item.episode,
                    feedTitle: item.feedTitle,
                    dateOverride: Date(timeIntervalSince1970: Double(item.favoritedAtEpochMs) / 1000),
                    dateAccessibilityLabel: "Favorited"
                )
            }
        } header: {
            sectionHeader("Favorites", systemImage: "star")
        } footer: {
            NavigationLink {
                FavoritesView()
            } label: {
                Text(store.favoriteEpisodes.count > previewLimit ? "See all Favorites" : "Open Favorites")
                    .font(.footnote)
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
    }

    @ViewBuilder
    private func homeSectionLink(title: String, systemImage: String, tab: RootTab, total: Int) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            if total > 0 {
                Text("\(total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Button {
                selectedTab = tab
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(title)")
        }
    }

    /// Episode-like items with `episode.title` + `feedTitle` (Continue / Inbox / Favorites).
    private func filterEpisodes<T>(_ items: [T]) -> [T] where T: HomeSearchableEpisode {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }
        return items.filter { item in
            if item.episode.title.localizedCaseInsensitiveContains(q) { return true }
            return item.feedTitle.localizedCaseInsensitiveContains(q)
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
}

/// Shared title/feed fields for Home section episode previews (Continue / Inbox / Favorites).
private protocol HomeSearchableEpisode {
    var episode: PodcastEpisode { get }
    var feedTitle: String { get }
}

extension HistoryEpisode: HomeSearchableEpisode {}
extension InboxEpisode: HomeSearchableEpisode {}
extension FavoriteEpisode: HomeSearchableEpisode {}

/// Sum of remaining seconds over the visible Home Continue preview rows (filter + soft-cap).
private struct ContinueRemainingSummary {
    var episodeCount: Int
    var remainingSeconds: Double
    var knownCount: Int
    var unknownCount: Int
}

