import SwiftUI

/// One multi-select + batch-action bar shared by the episode lists (Inbox, Episodes, History,
/// Favorites, Downloads). Rows are tagged with the episode id; `List(selection:)` + this modifier
/// supply the Select/Done toolbar button and the bottom batch bar.
/// Android refs: app/src/main/res/menu/multi_select_options.xml and
/// episodes_apply_action_speeddial.xml (add/remove queue, mark played/unplayed, download,
/// delete, favorite on every episode list).
struct EpisodeMultiSelectModifier: ViewModifier {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var downloads: DownloadService
    @EnvironmentObject private var settings: AppSettings
    @Binding var selection: Set<String>
    /// Episodes the list currently shows; selection is resolved against these.
    let episodes: [PodcastEpisode]
    /// Queue only: Move to top / Move to bottom (Android episodes_apply_action_speeddial move_to_top_item /
    /// move_to_bottom_item, shown by QueueFragment).
    var queueActions = false
    @State private var editMode: EditMode = .inactive
    @State private var confirmDelete = false

    private var isSelecting: Bool { editMode.isEditing }

    private var selected: [PodcastEpisode] {
        episodes.filter { selection.contains($0.id) }
    }

    func body(content: Content) -> some View {
        content
            .environment(\.editMode, $editMode)
            .environment(\.startEpisodeSelection, StartEpisodeSelection { id in
                withAnimation {
                    selection = [id]
                    editMode = .active
                }
            })
            #if DEBUG
            // Screenshots: `-APDebugSelectFirst` does what long-press > Select does on the first episode.
            .task {
                guard ProcessInfo.processInfo.arguments.contains("-APDebugSelectFirst"), let first = episodes.first else { return }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                editMode = .active
                try? await Task.sleep(nanoseconds: 500_000_000)
                selection = [first.id]
            }
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSelecting ? String(localized: "Done") : String(localized: "Select")) {
                        withAnimation {
                            editMode = isSelecting ? .inactive : .active
                            if !isSelecting { selection.removeAll() }
                        }
                    }
                    .disabled(episodes.isEmpty && !isSelecting)
                    .accessibilityHint(String(localized: "Selects several episodes to apply one action to all of them."))
                }
                // Batch controls in the navigation bar. A `.bottomBar` toolbar item (and anything pinned to the
                // list's bottom) ends up under the tab bar and mini player inside a TabView tab, so selecting
                // showed no actions. On compact widths (iPhone SE) a second trailing item next to "Done" and the
                // screen's own "…" menu was dropped, so select-all and the batch actions share ONE leading menu.
                // Android: the multi-select toolbar's select-all plus the floatingSelectMenu SpeedDial.
                if isSelecting {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button(selection.count == episodes.count ? String(localized: "Deselect all") : String(localized: "Select all")) {
                                if selection.count == episodes.count {
                                    selection.removeAll()
                                } else {
                                    selection = Set(episodes.map(\.id))
                                }
                            }
                            Section(String(format: String(localized: "%lld selected"), selection.count)) {
                                batchActions
                            }
                            .disabled(selection.isEmpty)
                        } label: {
                            Label("Actions", systemImage: "checklist")
                        }
                        .accessibilityValue(String(format: String(localized: "%lld selected"), selection.count))
                    }
                }
            }
            .confirmationDialog(
                "Delete downloads?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete downloads", role: .destructive) {
                    selected.filter { downloads.isDownloaded($0) }.forEach { downloads.delete($0) }
                    finish()
                }
                Button("Cancel", role: .cancel) {}
            }
    }

    @ViewBuilder
    private var batchActions: some View {
        if queueActions, !settings.queueLocked {
            Button {
                Self.queueMoveOrder(selection: selection, queue: store.queue, toTop: true)
                    .forEach { store.moveQueueItemToTop($0) }
                finish()
            } label: {
                Label("Move to top", systemImage: "arrow.up.to.line")
            }
            Button {
                Self.queueMoveOrder(selection: selection, queue: store.queue, toTop: false)
                    .forEach { store.moveQueueItemToBottom($0) }
                finish()
            } label: {
                Label("Move to bottom", systemImage: "arrow.down.to.line")
            }
            Divider()
        }
        Button {
            // One batch so Front / After current keep the selection order (Android addQueueItem).
            store.enqueue(selected.filter { !store.isInQueue($0.id) })
            finish()
        } label: {
            Label("Add to queue", systemImage: "text.append")
        }
        Button {
            selected.filter { store.isInQueue($0.id) }.forEach { store.removeFromQueue($0) }
            finish()
        } label: {
            Label("Remove from queue", systemImage: "text.badge.minus")
        }
        Button {
            selected.forEach { store.markPlayed($0.id) }
            finish()
        } label: {
            Label("Mark played", systemImage: "checkmark.circle")
        }
        Button {
            selected.forEach { store.markUnplayed($0.id) }
            finish()
        } label: {
            Label("Mark unplayed", systemImage: "circle")
        }
        Button {
            selected.filter { !store.isFavorite($0.id) }.forEach { store.toggleFavorite($0.id) }
            finish()
        } label: {
            Label("Add to favorites", systemImage: "star")
        }
        Button {
            let toDownload = selected.filter {
                EpisodeDownloadActions.canManageDownload(for: $0) && !downloads.isDownloaded($0)
                    && !downloads.inProgress.contains($0.id)
            }
            Task { for episode in toDownload { await downloads.download(episode) } }
            finish()
        } label: {
            Label("Download", systemImage: "arrow.down.circle")
        }
        Button(role: .destructive) {
            confirmDelete = true
        } label: {
            Label("Delete downloads", systemImage: "trash")
        }
    }

    /// Order to apply one-by-one moves so the selected episodes keep their queue order at the top or bottom
    /// (Android DBWriter.moveQueueItemsToTop/Bottom keep the relative order too).
    static func queueMoveOrder(selection: Set<String>, queue: [PodcastEpisode], toTop: Bool) -> [PodcastEpisode] {
        let picked = queue.filter { selection.contains($0.id) }
        return toTop ? picked.reversed() : picked
    }

    private func finish() {
        selection.removeAll()
        editMode = .inactive
    }
}

extension View {
    func episodeMultiSelect(selection: Binding<Set<String>>, episodes: [PodcastEpisode], queueActions: Bool = false) -> some View {
        modifier(EpisodeMultiSelectModifier(selection: selection, episodes: episodes, queueActions: queueActions))
    }
}

/// Long-press "Select" (Android feeditemlist_context multi_select): enters multi-select with that
/// episode already selected. nil in lists without multi-select.
struct StartEpisodeSelection {
    let start: (String) -> Void
    func callAsFunction(_ episodeId: String) { start(episodeId) }
}

private struct StartEpisodeSelectionKey: EnvironmentKey {
    static let defaultValue: StartEpisodeSelection? = nil
}

extension EnvironmentValues {
    var startEpisodeSelection: StartEpisodeSelection? {
        get { self[StartEpisodeSelectionKey.self] }
        set { self[StartEpisodeSelectionKey.self] = newValue }
    }
}

/// The "Select" long-press entry; hidden where the list has no multi-select or is already selecting.
struct SelectEpisodeMenuItem: View {
    @Environment(\.startEpisodeSelection) private var startSelection
    @Environment(\.editMode) private var editMode
    let episodeId: String

    var body: some View {
        if let startSelection, editMode?.wrappedValue.isEditing != true {
            Button {
                startSelection(episodeId)
            } label: {
                Label("Select", systemImage: "checkmark.circle")
            }
            .accessibilityHint(String(localized: "Starts selecting episodes, with this one already selected."))
        }
    }
}

/// Long-press "Select" (Android feeditemlist_context multi_select): enters multi-select with that
/// episode already selected. nil in lists without multi-select.
struct StartEpisodeSelection {
    let start: (String) -> Void
    func callAsFunction(_ episodeId: String) { start(episodeId) }
}

private struct StartEpisodeSelectionKey: EnvironmentKey {
    static let defaultValue: StartEpisodeSelection? = nil
}

extension EnvironmentValues {
    var startEpisodeSelection: StartEpisodeSelection? {
        get { self[StartEpisodeSelectionKey.self] }
        set { self[StartEpisodeSelectionKey.self] = newValue }
    }
}

/// The "Select" long-press entry; hidden where the list has no multi-select or is already selecting.
struct SelectEpisodeMenuItem: View {
    @Environment(\.startEpisodeSelection) private var startSelection
    @Environment(\.editMode) private var editMode
    let episodeId: String

    var body: some View {
        if let startSelection, editMode?.wrappedValue.isEditing != true {
            Button {
                startSelection(episodeId)
            } label: {
                Label("Select", systemImage: "checkmark.circle")
            }
            .accessibilityHint(String(localized: "Starts selecting episodes, with this one already selected."))
        }
    }
}
