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
            // home.xml action_search → Android SearchFragment: feeds and episodes across the library.
            NavigationLink {
                LibrarySearchScreen()
            } label: {
                Label("Search library", systemImage: "magnifyingglass")
            }
        } label: {
            Label("Home actions", systemImage: "ellipsis.circle")
        }
    }
}

/// Pushed full-library search (podcasts + episodes), same results as Inbox library search.
/// Android ref: app/src/main/java/de/danoeh/antennapod/ui/screen/SearchFragment.java.
struct LibrarySearchScreen: View {
    @State private var query = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        Group {
            if debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView.search
            } else {
                List { LibrarySearchResultsView(query: debouncedQuery) }
            }
        }
        .navigationTitle("Search library")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search library")
        .onChange(of: query) { _, newValue in
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                debouncedQuery = newValue
            }
        }
        .onDisappear { debounceTask?.cancel() }
    }
}
