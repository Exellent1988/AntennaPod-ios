import SwiftUI

/// Multi-select for the Subscriptions list (list mode). Same pattern as EpisodeMultiSelect (QMS-02):
/// Select/Done in the toolbar, one leading "Actions" menu with Select all and the batch actions.
/// Android: ui/screen/subscriptions/FeedMultiSelectActionHandler.java with nav_feed_action_speeddial.xml
/// (remove_archive_feed, keep_updated, notify_new_episodes, autodownload, autoDeleteDownload,
/// playback_speed, edit_tags, remove_all_inbox_item, share_feed). Per-feed values go through
/// PodcastStore.updateFeedSettings, the same store path podcast settings use.
struct FeedMultiSelectModifier: ViewModifier {
    @EnvironmentObject private var store: PodcastStore
    @Binding var selection: Set<UUID>
    /// Feeds the list currently shows; selection is resolved against these.
    let feeds: [PodcastFeed]
    /// Reports Select mode to the screen (Subscriptions hides its "+" button while selecting).
    var onSelectingChange: ((Bool) -> Void)? = nil
    @State private var editMode: EditMode = .inactive
    @State private var confirmUnsubscribe = false
    @State private var confirmInboxRemoval = false
    /// Android edit_tags for the selection (TagSettingsDialog with several FeedPreferences).
    @State private var tagsFeedIds: TagSelection?

    struct TagSelection: Identifiable {
        let id = UUID()
        let feedIds: [UUID]
    }

    private var isSelecting: Bool { editMode.isEditing }

    private var selected: [PodcastFeed] {
        feeds.filter { selection.contains($0.id) }
    }

    func body(content: Content) -> some View {
        content
            .environment(\.editMode, $editMode)
            .onChange(of: editMode.isEditing) { _, selecting in onSelectingChange?(selecting) }
            #if DEBUG
            // Screenshots: -APDebugSelectFirstFeed enters selection with the first podcast selected.
            .task {
                guard ProcessInfo.processInfo.arguments.contains("-APDebugSelectFirstFeed"), let first = feeds.first else { return }
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
                    .disabled(feeds.isEmpty && !isSelecting)
                }
                if isSelecting {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button(selection.count == feeds.count ? String(localized: "Deselect all") : String(localized: "Select all")) {
                                if selection.count == feeds.count {
                                    selection.removeAll()
                                } else {
                                    selection = Set(feeds.map(\.id))
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
            .confirmationDialog("Unsubscribe?", isPresented: $confirmUnsubscribe, titleVisibility: .visible) {
                Button("Unsubscribe", role: .destructive) {
                    // Same per-feed path as the swipe / long-press Unsubscribe; downloaded files are kept.
                    selected.forEach { store.unsubscribe($0) }
                    finish()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Unsubscribes from \(selected.count) podcasts. Downloaded files are kept.")
            }
            .confirmationDialog("Remove all from inbox?", isPresented: $confirmInboxRemoval, titleVisibility: .visible) {
                Button("Remove all from inbox", role: .destructive) {
                    selected.forEach { store.archiveAllInbox(inFeed: $0.id) }
                    finish()
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $tagsFeedIds, onDismiss: finish) { pick in
                FeedTagsSheet(
                    feedIds: pick.feedIds,
                    title: String(format: String(localized: "%lld selected"), pick.feedIds.count)
                )
            }
    }

    @ViewBuilder
    private var batchActions: some View {
        overrideMenu("Keep updated", systemImage: "arrow.clockwise") { $0.keepUpdated = $1 }
        overrideMenu("Auto-download", systemImage: "arrow.down.circle") { $0.autoDownload = $1 }
        overrideMenu("Auto-delete", systemImage: "trash.circle") { $0.autoDeleteAfterPlaying = $1 }
        overrideMenu("Notify on new episodes", systemImage: "bell") { $0.notifyOnNewEpisodes = $1 }
        Menu {
            Button("Use global") { apply { $0.playbackSpeed = nil } }
            ForEach(AppSettings.storedSpeedPresets(), id: \.self) { speed in
                Button(String(format: "%.2gx", speed)) { apply { $0.playbackSpeed = speed } }
            }
        } label: {
            Label("Playback speed", systemImage: "speedometer")
        }
        Button {
            tagsFeedIds = TagSelection(feedIds: selected.map(\.id))
        } label: {
            Label("Edit tags", systemImage: "tag")
        }
        // Android FeedMenuHandler.java:40: share_feed only when exactly one non-local podcast is selected.
        if selected.count == 1, let url = Self.shareableFeedURL(selected[0]) {
            ShareLink(item: url) {
                Label("Share feed URL", systemImage: "square.and.arrow.up")
            }
        }
        Button {
            confirmInboxRemoval = true
        } label: {
            Label("Remove all from inbox", systemImage: "tray.and.arrow.up")
        }
        Divider()
        Button(role: .destructive) {
            confirmUnsubscribe = true
        } label: {
            Label("Unsubscribe", systemImage: "trash")
        }
    }

    private func overrideMenu(
        _ title: LocalizedStringKey,
        systemImage: String,
        set: @escaping (inout FeedSettings, PerFeedOverride) -> Void
    ) -> some View {
        Menu {
            ForEach(PerFeedOverride.allCases) { value in
                Button(value.label) { apply { set(&$0, value) } }
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    private func apply(_ mutate: (inout FeedSettings) -> Void) {
        for feed in selected {
            store.updateFeedSettings(for: feed.id, mutate)
        }
        finish()
    }

    /// http(s) feed URL, nil for local folders (Android: !isLocalFeed()).
    static func shareableFeedURL(_ feed: PodcastFeed) -> URL? {
        guard let url = URL(string: feed.feedUrl), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    private func finish() {
        selection.removeAll()
        editMode = .inactive
    }
}

extension View {
    /// Android FeedMultiSelectActionHandler for the Subscriptions list.
    func feedMultiSelect(selection: Binding<Set<UUID>>, feeds: [PodcastFeed],
                         onSelectingChange: ((Bool) -> Void)? = nil) -> some View {
        modifier(FeedMultiSelectModifier(selection: selection, feeds: feeds, onSelectingChange: onSelectingChange))
    }
}

/// Grid-mode selection (Android SubscriptionsRecyclerAdapter in action mode: tap toggles, select icon on the
/// cover, SelectableAdapter). The grid is one List row, so `List(selection:)` can't select single cells;
/// while Select is on (editMode from FeedMultiSelectModifier) a tap layer over each cell toggles its id.
struct FeedGridSelectionModifier: ViewModifier {
    @Environment(\.editMode) private var editMode
    @Binding var selection: Set<UUID>
    let feedId: UUID

    private var isSelecting: Bool { editMode?.wrappedValue.isEditing == true }
    private var isSelected: Bool { selection.contains(feedId) }

    /// Android SubscriptionsRecyclerAdapter.onBindViewHolder: a selected card gets a 12dp margin (cover shrinks),
    /// animated over 100 ms (animateCardMargin).
    static func cardInset(selecting: Bool, selected: Bool) -> CGFloat {
        selecting && selected ? 12 : 0
    }

    func body(content: Content) -> some View {
        content
            .padding(Self.cardInset(selecting: isSelecting, selected: isSelected))
            .animation(.easeOut(duration: 0.1), value: isSelected)
            .animation(.easeOut(duration: 0.1), value: isSelecting)
            .overlay {
                if isSelecting {
                    Button {
                        if isSelected { selection.remove(feedId) } else { selection.insert(feedId) }
                    } label: {
                        Color.clear.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .overlay(alignment: .topLeading) {
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.white)
                        .background(Circle().fill(.black.opacity(0.25)))
                        .padding(6)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityAddTraits(isSelecting && isSelected ? .isSelected : [])
    }
}

extension View {
    func feedGridSelectable(selection: Binding<Set<UUID>>, feedId: UUID) -> some View {
        modifier(FeedGridSelectionModifier(selection: selection, feedId: feedId))
    }
}
