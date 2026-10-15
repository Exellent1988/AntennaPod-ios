import SwiftUI

/// Configurable per-list swipe actions, modelled on Android
/// app/src/main/java/de/danoeh/antennapod/ui/swipeactions/SwipeActions.java, SwipeAction.java and
/// SwipeActionsDialog.java (plus ui/preferences/src/main/res/xml/preferences_swipe.xml).
/// `.standard` keeps each list's built-in swipe buttons, so defaults match the previous behaviour.
enum EpisodeSwipeAction: String, CaseIterable, Identifiable {
    case standard, none, toggleQueue, togglePlayed, toggleFavorite, download, deleteDownload, archive
    // Android RemoveFromHistorySwipeAction, MoveToTopSwipeAction, MoveToBottomSwipeAction.
    case removeFromHistory, moveToTop, moveToBottom
    // Android ShareSwipeAction (opens ShareDialog: episode / podcast link).
    case share
    var id: String { rawValue }

    /// Choices for one list, following SwipeActionsDialog: Queue gets move to top/bottom + remove,
    /// others add to queue; no download in Downloads; remove from inbox (iOS: Archive) not in
    /// Downloads/Queue/History; no delete or played toggle in Inbox; remove from history only in History.
    static func available(for list: SwipeList) -> [EpisodeSwipeAction] {
        var a: [EpisodeSwipeAction] = [.standard, .none]
        if list == .queue { a += [.moveToTop, .moveToBottom] }
        a.append(.toggleQueue)
        if list != .downloads { a.append(.download) }
        if ![.downloads, .queue, .history].contains(list) { a.append(.archive) }
        if list != .inbox { a.append(.deleteDownload) }
        a.append(.toggleFavorite)
        if list == .history { a.append(.removeFromHistory) }
        if list != .inbox { a.append(.togglePlayed) }
        a.append(.share)
        return a
    }

    /// Android SwipeActions.getPrefsWithDefaults (first value = swipe right = iOS leading edge).
    /// FeedItemlistFragment has no case there and falls through to the All episodes default.
    static func androidDefault(for list: SwipeList) -> (leading: EpisodeSwipeAction, trailing: EpisodeSwipeAction) {
        switch list {
        case .inbox: return (.toggleQueue, .archive)
        case .queue: return (.toggleQueue, .toggleQueue)
        case .downloads: return (.deleteDownload, .deleteDownload)
        case .history: return (.removeFromHistory, .removeFromHistory)
        case .favorites: return (.toggleFavorite, .toggleFavorite)
        case .episodes, .feed: return (.toggleFavorite, .download)
        }
    }

    var label: String {
        switch self {
        case .standard: return String(localized: "Default for this list")
        case .none: return String(localized: "No action")
        case .toggleQueue: return String(localized: "Add to / remove from queue")
        case .togglePlayed: return String(localized: "Mark played / unplayed")
        case .toggleFavorite: return String(localized: "Add to / remove from favorites")
        case .download: return String(localized: "Download")
        case .deleteDownload: return String(localized: "Delete download")
        case .archive: return String(localized: "Archive / restore")
        case .removeFromHistory: return String(localized: "Remove from History")
        case .moveToTop: return String(localized: "Move to top")
        case .moveToBottom: return String(localized: "Move to bottom")
        case .share: return String(localized: "Share")
        }
    }
}

/// Lists with swipe actions (Android SwipeActions tags: QueueFragment, InboxFragment, …).
enum SwipeList: String, CaseIterable, Identifiable {
    case inbox, queue, episodes, downloads, history, favorites, feed
    var id: String { rawValue }

    var label: String {
        switch self {
        case .inbox: return String(localized: "Inbox")
        case .queue: return String(localized: "Queue")
        case .episodes: return String(localized: "Episodes")
        case .downloads: return String(localized: "Downloads")
        case .history: return String(localized: "History")
        case .favorites: return String(localized: "Favorites")
        case .feed: return String(localized: "Podcast episodes")
        }
    }

    func key(_ edge: HorizontalEdge) -> String {
        // AppSettings.swipeActions key; the pre-AppSettings @AppStorage key was "swipe." + this.
        "\(rawValue).\(edge == .leading ? "leading" : "trailing")"
    }
}

/// Wraps one swipe edge: shows the list's own buttons for `.standard`, else the chosen action.
struct SwipeSlot<Standard: View>: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var downloads: DownloadService
    @EnvironmentObject private var settings: AppSettings
    let list: SwipeList
    let edge: HorizontalEdge
    let episode: PodcastEpisode
    let standard: Standard

    init(_ list: SwipeList, _ edge: HorizontalEdge, episode: PodcastEpisode, @ViewBuilder standard: () -> Standard) {
        self.list = list
        self.edge = edge
        self.episode = episode
        self.standard = standard()
    }

    private var action: EpisodeSwipeAction { settings.swipeAction(list, edge) }

    var body: some View {
        switch action {
        case .standard:
            standard
        case .none:
            EmptyView()
        case .toggleQueue:
            let queued = store.isInQueue(episode.id)
            Button {
                if queued { store.removeFromQueue(episode) } else { store.enqueue(episode) }
            } label: {
                Label(queued ? String(localized: "Remove from queue") : String(localized: "Add to queue"),
                      systemImage: queued ? "text.badge.minus" : "text.append")
            }
            .tint(.indigo)
        case .togglePlayed:
            let played = store.isPlayed(episode.id)
            Button {
                store.togglePlayed(episode.id)
            } label: {
                Label(played ? String(localized: "Mark unplayed") : String(localized: "Mark played"),
                      systemImage: played ? "circle" : "checkmark.circle")
            }
            .tint(.green)
        case .toggleFavorite:
            let fav = store.isFavorite(episode.id)
            Button {
                store.toggleFavorite(episode.id)
            } label: {
                Label(fav ? String(localized: "Unfavorite") : String(localized: "Favorite"),
                      systemImage: fav ? "star.slash" : "star")
            }
            .tint(.yellow)
        case .download:
            if EpisodeDownloadActions.canManageDownload(for: episode), !downloads.isDownloaded(episode) {
                Button {
                    Task { await downloads.download(episode) }
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .tint(.blue)
            }
        case .deleteDownload:
            if downloads.isDownloaded(episode) {
                Button(role: .destructive) {
                    downloads.delete(episode)
                } label: {
                    Label("Delete download", systemImage: "trash")
                }
            }
        case .archive:
            let archived = store.isArchived(episode.id)
            Button {
                store.toggleArchived(episode.id)
            } label: {
                Label(archived ? String(localized: "Restore") : String(localized: "Archive"),
                      systemImage: archived ? "arrow.uturn.backward" : "archivebox")
            }
            .tint(.orange)
        case .removeFromHistory:
            Button(role: .destructive) {
                store.removeFromHistory(episode.id)
            } label: {
                Label("Remove from History", systemImage: "clock.badge.xmark")
            }
        case .share:
            // Same link and text as the episode long-press Share (episode page, else media/feed link).
            let feed = store.feed(containingEpisodeId: episode.id)
            if let url = episode.shareURL(feed: feed) {
                ShareLink(
                    item: url,
                    subject: Text(episode.title),
                    message: Text(episode.shareMessage(feedTitle: feed.map { store.displayTitle(for: $0) }))
                ) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .tint(.blue)
            }
        case .moveToTop, .moveToBottom:
            if store.isInQueue(episode.id), !settings.queueLocked {
                let top = action == .moveToTop
                Button {
                    if top { store.moveQueueItemToTop(episode) } else { store.moveQueueItemToBottom(episode) }
                } label: {
                    Label(top ? String(localized: "Move to top") : String(localized: "Move to bottom"),
                          systemImage: top ? "arrow.up.to.line" : "arrow.down.to.line")
                }
                .tint(.indigo)
            }
        }
    }
}

/// Settings → User interface → Swipe actions (Android SwipeActionsDialog per screen).
/// `lists` narrows it to one screen when opened from that list's ⋯ menu.
struct SwipeActionsSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    var lists: [SwipeList] = SwipeList.allCases

    var body: some View {
        Form {
            ForEach(lists) { list in
                Section(list.label) {
                    picker(String(localized: "Swipe right"), list, .leading)
                    picker(String(localized: "Swipe left"), list, .trailing)
                }
            }
            Section {
                Button("Use AntennaPod defaults") {
                    for list in lists {
                        let d = EpisodeSwipeAction.androidDefault(for: list)
                        settings.setSwipeAction(d.leading, list, .leading)
                        settings.setSwipeAction(d.trailing, list, .trailing)
                    }
                }
                .accessibilityHint(String(localized: "Sets the swipe actions AntennaPod for Android uses on these lists."))
                Button("Reset to defaults", role: .destructive) {
                    if lists.count == SwipeList.allCases.count {
                        settings.swipeActions = [:]
                    } else {
                        for list in lists {
                            settings.setSwipeAction(.standard, list, .leading)
                            settings.setSwipeAction(.standard, list, .trailing)
                        }
                    }
                }
            }
        }
        .navigationTitle("Swipe actions")
    }

    private func picker(_ title: String, _ list: SwipeList, _ edge: HorizontalEdge) -> some View {
        let current = settings.swipeAction(list, edge)
        var options = EpisodeSwipeAction.available(for: list)
        if !options.contains(current) { options.append(current) }
        return Picker(title, selection: Binding(
            get: { settings.swipeAction(list, edge) },
            set: { settings.setSwipeAction($0, list, edge) }
        )) {
            ForEach(options) { action in
                Text(action.label).tag(action)
            }
        }
    }
}

/// One list's swipe settings as a sheet, opened from that list's ⋯ menu.
struct SwipeActionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let list: SwipeList

    var body: some View {
        NavigationStack {
            SwipeActionsSettingsView(lists: [list])
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

/// ⋯ menu entry "Swipe actions" for a list.
struct SwipeActionsMenuButton: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Label("Swipe actions", systemImage: "hand.draw")
        }
        .accessibilityHint(String(localized: "Choose what swiping an episode left or right does in this list."))
    }
}
