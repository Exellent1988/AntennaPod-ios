import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            SubscriptionsView()
                .tabItem {
                    Label("Subscriptions", systemImage: "square.stack.fill")
                }
            DownloadsView()
                .tabItem {
                    Label("Downloads", systemImage: "arrow.down.circle")
                }
            QueueView()
                .tabItem {
                    Label("Queue", systemImage: "list.bullet")
                }
        }
        .safeAreaInset(edge: .bottom) {
            MiniPlayerView()
        }
    }
}
