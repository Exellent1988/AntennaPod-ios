import SwiftUI

struct SubscriptionsView: View {
    @EnvironmentObject private var store: PodcastStore
    @State private var showAdd = false
    @State private var showOpmlSheet = false
    @State private var searchText = ""
    @State private var tagFilter: SubscriptionTagFilter = .all
    @State private var groupByTag = true

    private var searchFilteredFeeds: [PodcastFeed] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return store.feeds }
        return store.matchingFeeds(query: q)
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
        NavigationStack {
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
                        HistoryView()
                    } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
                    NavigationLink {
                        TopListsView()
                    } label: {
                        Label("Discover", systemImage: "chart.bar")
                    }
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
                        description: Text("Search Apple Podcasts, open Discover for charts, add by feed URL, or import an OPML file.")
                    )
                } else if tagFilteredFeeds.isEmpty {
                    ContentUnavailableView(
                        "No matching podcasts",
                        systemImage: "magnifyingglass",
                        description: Text(
                            searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? "No subscriptions match this tag filter."
                                : "No subscriptions match your library search."
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
            .navigationDestination(for: PodcastFeed.self) { feed in
                FeedDetailView(feed: feed)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showOpmlSheet = true
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.square")
                    }
                    .accessibilityLabel("Import or export OPML")
                }
            }
            .sheet(isPresented: $showAdd) {
                AddFeedView()
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
                    ProgressView("Loading feed…")
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
        }
    }

    @ViewBuilder
    private func feedRow(_ feed: PodcastFeed) -> some View {
        NavigationLink(value: feed) {
            VStack(alignment: .leading, spacing: 4) {
                Text(feed.title)
                    .font(.headline)
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
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                store.unsubscribe(feed)
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
