import SwiftUI

/// Landing tab: honest previews of Continue listening, Inbox, Queue, and recently updated feeds.
struct HomeView: View {
    @EnvironmentObject private var store: PodcastStore
    @Binding var selectedTab: RootTab

    private let previewLimit = 5
    private let feedsLimit = 5

    private var continueItems: [HistoryEpisode] {
        Array(store.continueListeningEpisodes.prefix(previewLimit))
    }

    private var inboxItems: [InboxEpisode] {
        Array(store.inboxEpisodes.prefix(previewLimit))
    }

    private var queueItems: [PodcastEpisode] {
        Array(store.queue.prefix(previewLimit))
    }

    private var recentFeeds: [PodcastFeed] {
        Array(store.recentlyUpdatedFeeds.prefix(feedsLimit))
    }

    private var hasAnyContent: Bool {
        !continueItems.isEmpty || !inboxItems.isEmpty || !queueItems.isEmpty || !recentFeeds.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HomeTopListsPreview()
                } header: {
                    sectionHeader("Discover", systemImage: "chart.bar")
                } footer: {
                    NavigationLink {
                        TopListsView()
                    } label: {
                        Text("See all charts")
                            .font(.footnote)
                    }
                }

                if !hasAnyContent {
                    ContentUnavailableView(
                        "Welcome",
                        systemImage: "house",
                        description: Text("Subscribe to podcasts to see continue listening, new episodes, your queue, and recently updated feeds here. Or use Discover above for Apple Charts.")
                    )
                } else {
                    if !continueItems.isEmpty {
                        Section {
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

                    if !inboxItems.isEmpty {
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

                    if !queueItems.isEmpty {
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

                    if !recentFeeds.isEmpty {
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
                }
            }
            .navigationTitle("Home")
            .navigationDestination(for: PodcastFeed.self) { feed in
                FeedDetailView(feed: feed)
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
}
