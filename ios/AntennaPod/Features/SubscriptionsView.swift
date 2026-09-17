import SwiftUI

struct SubscriptionsView: View {
    @EnvironmentObject private var store: PodcastStore
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                if store.feeds.isEmpty {
                    ContentUnavailableView(
                        "No subscriptions",
                        systemImage: "dot.radiowaves.left.and.right",
                        description: Text("Add a podcast by feed URL to get started.")
                    )
                } else {
                    ForEach(store.feeds) { feed in
                        NavigationLink(value: feed) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(feed.title)
                                    .font(.headline)
                                Text("\(feed.episodes.count) episodes")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
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
            }
            .navigationTitle("Subscriptions")
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
            }
            .sheet(isPresented: $showAdd) {
                AddFeedView()
            }
            .overlay {
                if store.isLoading {
                    ProgressView("Loading feed…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}
