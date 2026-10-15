import PodcastCore
import SwiftUI

/// DEBUG-only screenshot hook for list filter / sort / charts.
/// `-APDebugListScreen episodes|queue|feed|statistics` shows that screen full-screen after
/// subscribing to a sample feed. `-APDebugListPreset after` applies a sample filter + sort
/// (`before` clears it). `-APDebugOpenFilterSheet YES` opens the filter sheet.
struct ListFilterDebugOverlay: ViewModifier {
    func body(content: Content) -> some View {
        #if DEBUG
        content.modifier(ListFilterDebugCover())
        #else
        content
        #endif
    }
}

#if DEBUG
private struct ListFilterDebugCover: ViewModifier {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var settings: AppSettings
    @State private var screen: String?

    func body(content: Content) -> some View {
        content
            .task {
                guard let requested = UserDefaults.standard.string(forKey: "APDebugListScreen") else { return }
                let url = UserDefaults.standard.string(forKey: "APDebugFeedURL") ?? "https://feeds.metaebene.me/freakshow/mp3"
                if !store.feeds.contains(where: { $0.feedUrl == url }) { _ = await store.subscribe(feedUrl: url) }
                if let feed = store.feeds.first {
                    let eps = Array(feed.episodes.prefix(12))
                    for (i, e) in eps.enumerated() {
                        if i % 3 == 0 { store.markPlayed(e.id, removeFromQueue: false) }
                        if i % 4 == 1 { store.saveProgress(episodeId: e.id, positionSeconds: 600, durationSeconds: max(e.durationSeconds, 1200)) }
                    }
                    if store.queue.isEmpty { store.queue = Array(eps.prefix(6)) }
                }
                switch UserDefaults.standard.string(forKey: "APDebugListPreset") {
                case "after":
                    let o = EpisodeListOptions(filter: .init([.unplayed, .notQueued]), sort: .durationLongShort)
                    settings.allEpisodesListOptions = o
                    if let id = store.feeds.first?.id { settings.setListOptions(o, forFeed: id) }
                    settings.queueKeepSortedOrder = .durationShortLong
                    store.applyQueueKeepSorted()
                case "before":
                    settings.allEpisodesListOptions = .init()
                    if let id = store.feeds.first?.id { settings.setListOptions(.init(), forFeed: id) }
                    settings.queueKeepSortedOrder = nil
                default: break
                }
                screen = requested
            }
            .fullScreenCover(isPresented: Binding(get: { screen != nil }, set: { if !$0 { screen = nil } })) {
                switch screen {
                case "queue": QueueView()
                case "statistics": NavigationStack { StatisticsView() }
                case "feed":
                    if let feed = store.feeds.first { NavigationStack { FeedDetailView(feed: feed) } }
                default: NavigationStack { AllEpisodesView() }
                }
            }
    }
}
#endif
