import SwiftUI

/// Configurable per-list swipe actions, modelled on Android
/// app/src/main/java/de/danoeh/antennapod/ui/swipeactions/SwipeActions.java, SwipeAction.java and
/// SwipeActionsDialog.java (plus ui/preferences/src/main/res/xml/preferences_swipe.xml).
/// `.standard` keeps each list's built-in swipe buttons, so defaults match the previous behaviour.
enum EpisodeSwipeAction: String, CaseIterable, Identifiable {
    case standard, none, toggleQueue, togglePlayed, toggleFavorite, download, deleteDownload, archive
    var id: String { rawValue }

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
        }
    }
}

/// Settings → User interface → Swipe actions (Android SwipeActionsDialog per screen).
struct SwipeActionsSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            ForEach(SwipeList.allCases) { list in
                Section(list.label) {
                    picker(String(localized: "Swipe right"), list, .leading)
                    picker(String(localized: "Swipe left"), list, .trailing)
                }
            }
            Section {
                Button("Reset to defaults", role: .destructive) {
                    settings.swipeActions = [:]
                }
            }
        }
        .navigationTitle("Swipe actions")
    }

    private func picker(_ title: String, _ list: SwipeList, _ edge: HorizontalEdge) -> some View {
        Picker(title, selection: Binding(
            get: { settings.swipeAction(list, edge) },
            set: { settings.setSwipeAction($0, list, edge) }
        )) {
            ForEach(EpisodeSwipeAction.allCases) { action in
                Text(action.label).tag(action)
            }
        }
    }
}
