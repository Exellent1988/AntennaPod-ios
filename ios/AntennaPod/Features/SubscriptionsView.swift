import SwiftUI

struct SubscriptionsView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var parental: ParentalControls
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

    /// Client-side list order after search/tag filters (no drag-reorder of subscriptions).
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
        }
    }

    /// Visible subscriptions after search; empty query shows full list under current sort.
    /// Matches feed **title** and optional **descriptionText** (no author/authorEmail on PodcastFeed).
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

    private var tagFilteredFeeds: [PodcastFeed] {
        let base = searchFilteredFeeds
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
    /// Feeds within each section follow `subscriptionsSort` (inherited from `searchFilteredFeeds`).
    private var groupedSections: [(title: String, feeds: [PodcastFeed])] {
        guard tagFilter == .all, groupByTag, !store.allTags.isEmpty else {
            return [("Podcasts", tagFilteredFeeds)]
        }
        var sections: [(title: String, feeds: [PodcastFeed])] = []
        for tag in store.allTags {
            let feeds = searchFilteredFeeds.filter { feed in
                store.tags(for: feed.id).contains(where: { FeedTags.equal($0, tag) })
            }
            if !feeds.isEmpty {
                sections.append((tag, feeds))
            }
        }
        let untagged = searchFilteredFeeds.filter { store.tags(for: $0.id).isEmpty }
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

    var body: some View {
        NavigationStack(path: $path) {
            List {
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

                if !store.feeds.isEmpty, !store.allTags.isEmpty || tagFilter != .all {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(filterChips) { chip in
                                    TagFilterChip(
                                        title: chip.label,
                                        selected: tagFilter == chip
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
                        description: Text(
                            isSearchFiltering
                                ? String(localized: "No subscriptions match your search.")
                                : String(localized: "No subscriptions match this tag filter.")
                        )
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
                    .accessibilityLabel("Refresh all")
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
                    .accessibilityLabel("Import or export OPML")
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
                    .accessibilityLabel("Sort subscriptions")
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
                    ProgressView("Refreshing feeds…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .onChange(of: store.tagsByFeedId) { _, _ in
                // Drop filter if the selected tag disappeared.
                if case .tag(let name) = tagFilter,
                   !store.allTags.contains(where: { FeedTags.equal($0, name) }) {
                    tagFilter = .all
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
                Button("Unsubscribe", role: .destructive) {
                    store.unsubscribe(feed)
                    feedPendingUnsubscribe = nil
                }
                Button("Cancel", role: .cancel) {
                    feedPendingUnsubscribe = nil
                }
            } message: { feed in
                Text(
                    "Unsubscribe from \"\(feed.title)\"? Removes this podcast from Subscriptions, its feed settings and tags, queue items from this feed, and favorites, archive, and playback history for its episodes. Downloaded files are kept."
                )
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

    @ViewBuilder
    private func feedRow(_ feed: PodcastFeed) -> some View {
        NavigationLink(value: feed) {
            HStack(alignment: .center, spacing: 12) {
                if LocalFolderFeed.isLocalFolderFeed(feed) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Local folder")
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
                        }
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
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                feedPendingUnsubscribe = feed
            } label: {
                Label("Unsubscribe", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                Task { await store.refresh(feed) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .tint(.blue)
        }
    }
}

private struct TagFilterChip: View {
    let title: String
    let selected: Bool
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
    }
}
