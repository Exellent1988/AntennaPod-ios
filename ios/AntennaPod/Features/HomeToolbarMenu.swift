import SwiftUI

/// Home toolbar overflow. Android ref: app/src/main/res/menu/home.xml
/// (action_search, refresh_item, homesettings_items).
struct HomeToolbarMenu: View {
    @EnvironmentObject private var store: PodcastStore

    var body: some View {
        Menu {
            // home.xml refresh_item
            Button {
                Task { await store.refreshAllFeeds() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .accessibilityHint(String(localized: "Refreshes all subscribed podcasts, same as pull to refresh."))
        } label: {
            Label("Home actions", systemImage: "ellipsis.circle")
        }
    }
}
