import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            InboxView()
                .tabItem {
                    Label("Inbox", systemImage: "tray.fill")
                }
            SubscriptionsView()
                .tabItem {
                    Label("Subscriptions", systemImage: "square.stack.fill")
                }
            QueueView()
                .tabItem {
                    Label("Queue", systemImage: "list.bullet")
                }
            DownloadsView()
                .tabItem {
                    Label("Downloads", systemImage: "arrow.down.circle")
                }
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .safeAreaInset(edge: .bottom) {
            MiniPlayerView()
        }
        .task {
            // Launch: refresh subscribed feeds if the global interval is due.
            await FeedRefreshCoordinator.refreshAllFeedsIfDue(store: store, settings: settings)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await FeedRefreshCoordinator.refreshAllFeedsIfDue(store: store, settings: settings)
            }
        }
        .onChange(of: settings.refreshInterval) { _, interval in
            FeedRefreshCoordinator.scheduleBackgroundRefresh(interval: interval)
        }
    }
}
