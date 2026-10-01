import SwiftUI

struct RootTabView: View {
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
    }
}
