import SwiftUI

/// Per-subscription overrides (Auto-download / Auto-delete after play / Keep updated / New episodes / Notifications / Skip intro·outro / Speed / Episode sort) + tags.
struct PerFeedSettingsView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var playback: PlaybackService

    let feedId: UUID
    let feedTitle: String

    @State private var newTagDraft = ""
    @State private var renameFrom: String?
    @State private var renameDraft = ""
    @State private var showRenameAlert = false
    @State private var tagPendingDelete: String?
    @State private var showCustomFeedSpeed = false

    private var current: FeedSettings {
        store.feedSettings(for: feedId)
    }

    private var assignedTags: [String] {
        store.tags(for: feedId)
    }

    private var suggestedTags: [String] {
        store.allTags.filter { existing in
            !assignedTags.contains(where: { FeedTags.equal($0, existing) })
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Auto-download", selection: autoDownloadBinding) {
                    ForEach(PerFeedOverride.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                Text(autoDownloadHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Delete after playing", selection: autoDeleteBinding) {
                    ForEach(PerFeedOverride.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .accessibilityLabel(String(localized: "Delete after playing"))
                .accessibilityHint(String(localized: "Use global, Always, or Never for deleting this podcast’s offline file when an episode is marked played. Favorites are always kept."))
                .accessibilityValue(current.autoDeleteAfterPlaying.label)
                Text(autoDeleteHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(autoDeleteHelp)
            } header: {
                Text("Downloads")
            }

            Section {
                Picker("Keep updated", selection: keepUpdatedBinding) {
                    ForEach(PerFeedOverride.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .accessibilityLabel(String(localized: "Keep updated"))
                .accessibilityHint(String(localized: "When Never, Refresh all and automatic refresh skip this podcast. Manual single-podcast refresh still works."))
                .accessibilityValue(current.keepUpdated.label)
                Text(keepUpdatedHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(keepUpdatedHelp)
            } header: {
                Text("Refresh")
            } footer: {
                Text("Refresh all (Subscriptions) and automatic Keep updated refresh respect Never. Manual single-podcast refresh still works.")
            }

            Section {
                Picker("New episodes", selection: newEpisodeActionBinding) {
                    ForEach(PerFeedNewEpisodeAction.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                Text(newEpisodeActionHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("New episodes")
            }

            Section {
                Picker("Notify on new episodes", selection: notifyBinding) {
                    ForEach(PerFeedOverride.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                Text(notifyHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Notifications")
            }

            Section {
                Picker("Skip intro", selection: skipIntroBinding) {
                    Text("Use global").tag(Optional<Int>.none)
                    ForEach(AppSettings.skipIntroOutroPresets, id: \.self) { secs in
                        Text(AppSettings.skipIntroOutroLabel(secs)).tag(Optional(secs))
                    }
                }
                Text(skipIntroHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Skip outro", selection: skipOutroBinding) {
                    Text("Use global").tag(Optional<Int>.none)
                    ForEach(AppSettings.skipIntroOutroPresets, id: \.self) { secs in
                        Text(AppSettings.skipIntroOutroLabel(secs)).tag(Optional(secs))
                    }
                }
                Text(skipOutroHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Playback speed", selection: playbackSpeedBinding) {
                    Text("Use global").tag(Optional<Float>.none)
                    ForEach(AppSettings.speedPresets, id: \.self) { speed in
                        Text(PlaybackService.formatPlaybackSpeed(speed)).tag(Optional(speed))
                    }
                    if let override = current.playbackSpeed, !AppSettings.speedPresets.contains(override) {
                        Text(PlaybackService.formatPlaybackSpeed(override))
                            .tag(Optional(override))
                    }
                }
                .accessibilityLabel(String(localized: "Playback speed"))
                .accessibilityHint(String(localized: "Use global, a preset, or Custom… for this podcast"))
                .accessibilityValue(playbackSpeedAccessibilityValue)
                Button(String(localized: "Custom…")) {
                    showCustomFeedSpeed = true
                }
                .accessibilityHint(String(localized: "Set a custom playback speed for this podcast between 0.50× and 3.00×."))
                Text(playbackSpeedHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(playbackSpeedHelp)
            } header: {
                Text("Playback")
            }

            Section {
                Picker("Episode sort", selection: episodeSortBinding) {
                    Text("Use global").tag(Optional<FeedEpisodeSort>.none)
                    ForEach(FeedEpisodeSort.allCases) { sort in
                        Label(sort.label, systemImage: sort.systemImage)
                            .tag(Optional(sort))
                    }
                }
                .accessibilityLabel(String(localized: "Episode sort"))
                .accessibilityHint(String(localized: "Use global, Newest first, or Oldest first for this podcast’s episode list. Does not follow itunes:type."))
                .accessibilityValue(episodeSortAccessibilityValue)
                Text(episodeSortHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(episodeSortHelp)
            } header: {
                Text("Episodes")
            }

            Section {
                if assignedTags.isEmpty {
                    Text("No tags yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(assignedTags, id: \.self) { tag in
                        HStack {
                            Image(systemName: "tag")
                                .foregroundStyle(.secondary)
                            Text(tag)
                            Spacer()
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                store.removeTag(tag, from: feedId)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(tag)
                        .accessibilityHint(String(localized: "Swipe to remove from this podcast; context menu to rename or delete everywhere"))
                        .contextMenu {
                            Button("Rename…") {
                                renameFrom = tag
                                renameDraft = tag
                                showRenameAlert = true
                            }
                            Button("Remove from podcast", role: .destructive) {
                                store.removeTag(tag, from: feedId)
                            }
                            Button("Delete tag everywhere", role: .destructive) {
                                tagPendingDelete = tag
                            }
                        }
                    }
                }

                if !suggestedTags.isEmpty {
                    ForEach(suggestedTags, id: \.self) { tag in
                        Button {
                            store.addTag(tag, to: feedId)
                        } label: {
                            Label(tag, systemImage: "plus.circle")
                        }
                    }
                }

                HStack {
                    TextField("New tag", text: $newTagDraft)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .onSubmit(addDraftTag)
                    Button("Add") { addDraftTag() }
                        .disabled(FeedTags.normalize(newTagDraft) == nil)
                }
            } header: {
                Text("Tags / Folders")
            } footer: {
                Text("A podcast can have several tags. Tags exist while assigned; removing the last use deletes the tag. Rename applies to every podcast using that name.")
            }

            if !current.isDefault {
                Section {
                    Button("Reset to global defaults", role: .destructive) {
                        store.setFeedSettings(.default, for: feedId)
                    }
                }
            }
        }
        .navigationTitle(feedTitle.isEmpty ? "Podcast settings" : feedTitle)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Rename tag", isPresented: $showRenameAlert) {
            TextField("Tag name", text: $renameDraft)
                .accessibilityLabel(String(localized: "Tag name"))
            Button("Cancel", role: .cancel) {
                renameFrom = nil
            }
            Button("Rename") {
                if let from = renameFrom {
                    store.renameTag(from: from, to: renameDraft)
                }
                renameFrom = nil
            }
            .accessibilityHint(String(localized: "Applies the new name to every podcast that uses this tag"))
        } message: {
            Text("Renames this tag on every podcast that uses it. Clear the name to delete it everywhere.")
        }
        .confirmationDialog(
            "Delete tag?",
            isPresented: Binding(
                get: { tagPendingDelete != nil },
                set: { if !$0 { tagPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete tag everywhere", role: .destructive) {
                if let tag = tagPendingDelete {
                    store.deleteTag(tag)
                }
                tagPendingDelete = nil
            }
            .accessibilityHint(String(localized: "Removes the tag from all podcasts; does not unsubscribe"))
            Button("Cancel", role: .cancel) {
                tagPendingDelete = nil
            }
        } message: {
            if let tag = tagPendingDelete {
                let count = store.feeds(withTag: tag).count
                Text(String(format: String(localized: "Removes “%@” from %lld podcasts. Does not unsubscribe or delete downloads."), tag, count))
            }
        }
        .sheet(isPresented: $showCustomFeedSpeed) {
            CustomPlaybackSpeedSheet(
                mode: .feedOverride,
                initialSpeed: current.playbackSpeed ?? appSettings.defaultPlaybackSpeed
            ) { clamped in
                store.updateFeedSettings(for: feedId) { $0.playbackSpeed = clamped }
            }
            .environmentObject(playback)
            .environmentObject(appSettings)
        }
    }

    private func addDraftTag() {
        let ok = store.addTag(newTagDraft, to: feedId)
        if ok {
            newTagDraft = ""
        }
    }

    private var autoDownloadBinding: Binding<PerFeedOverride> {
        Binding(
            get: { current.autoDownload },
            set: { value in
                store.updateFeedSettings(for: feedId) { $0.autoDownload = value }
            }
        )
    }

    private var autoDeleteBinding: Binding<PerFeedOverride> {
        Binding(
            get: { current.autoDeleteAfterPlaying },
            set: { value in
                store.updateFeedSettings(for: feedId) { $0.autoDeleteAfterPlaying = value }
            }
        )
    }

    private var keepUpdatedBinding: Binding<PerFeedOverride> {
        Binding(
            get: { current.keepUpdated },
            set: { value in
                store.updateFeedSettings(for: feedId) { $0.keepUpdated = value }
            }
        )
    }

    private var notifyBinding: Binding<PerFeedOverride> {
        Binding(
            get: { current.notifyOnNewEpisodes },
            set: { value in
                store.updateFeedSettings(for: feedId) { $0.notifyOnNewEpisodes = value }
            }
        )
    }

    private var newEpisodeActionBinding: Binding<PerFeedNewEpisodeAction> {
        Binding(
            get: { current.newEpisodeAction },
            set: { value in
                store.updateFeedSettings(for: feedId) { $0.newEpisodeAction = value }
            }
        )
    }

    private var newEpisodeActionHelp: String {
        let global = appSettings.newEpisodeAction.label
        switch current.newEpisodeAction {
        case .useGlobal:
            return "Follows Settings → New episodes (currently \(global)). Queue+download is only available as the global choice."
        case .inboxOnly:
            return "New episodes for this podcast stay in Inbox only — not added to Queue, even when global adds to Queue."
        case .addToQueue:
            return "Newly appeared episodes for this podcast are added to Queue (no auto-download from this override). Inbox still lists them while unplayed."
        }
    }

    private var autoDownloadHelp: String {
        let global = appSettings.autoDownloadEnabled ? String(localized: "on") : String(localized: "off")
        switch current.autoDownload {
        case .useGlobal:
            return String(localized: "Follows Settings → Auto-download (currently \(global)). Cap and Wi‑Fi-only still apply globally. Only newly appeared episodes after refresh are candidates.")
        case .always:
            return String(localized: "Always enqueue newly appeared episodes after refresh for this podcast, even when global Auto-download is off. Cap and Wi‑Fi-only still apply.")
        case .never:
            return String(localized: "Never auto-download this podcast, even when global Auto-download is on. Manual Download still works.")
        }
    }

    private var autoDeleteHelp: String {
        let global = appSettings.autoDeleteAfterPlaying ? String(localized: "on") : String(localized: "off")
        switch current.autoDeleteAfterPlaying {
        case .useGlobal:
            return String(
                format: String(localized: "Follows Settings → Delete episode after playing (currently %@). Favorites still keep their offline files. Defers while that local file is the active player item."),
                global
            )
        case .always:
            return String(localized: "Always delete this podcast’s offline file when an episode is marked played, even when the global toggle is off. Favorites still keep their offline files.")
        case .never:
            return String(localized: "Never auto-delete this podcast’s offline files after playing, even when the global toggle is on. Manual Delete download still works.")
        }
    }

    private var keepUpdatedHelp: String {
        switch current.keepUpdated {
        case .useGlobal, .always:
            return String(localized: "Included in Refresh all and automatic Keep updated refresh (Subscriptions toolbar, Home/Inbox pull-to-refresh, launch/foreground interval). “Always” matches Use global until a global exclude exists.")
        case .never:
            return String(localized: "Skipped by Refresh all and automatic Keep updated refresh. You can still refresh this podcast alone from Subscriptions (swipe) or Feed detail.")
        }
    }

    private var notifyHelp: String {
        let global = appSettings.notifyOnNewEpisodes ? "on" : "off"
        switch current.notifyOnNewEpisodes {
        case .useGlobal:
            return "Follows Settings → Notify on new episodes (currently \(global)). System permission still required."
        case .always:
            return "Notify for this podcast even when the global toggle is off (permission still required)."
        case .never:
            return "No local notification for this podcast, even when the global toggle is on."
        }
    }

    private var skipIntroBinding: Binding<Int?> {
        Binding(
            get: { current.skipIntroSeconds },
            set: { value in
                store.updateFeedSettings(for: feedId) { $0.skipIntroSeconds = value }
            }
        )
    }

    private var skipOutroBinding: Binding<Int?> {
        Binding(
            get: { current.skipOutroSeconds },
            set: { value in
                store.updateFeedSettings(for: feedId) { $0.skipOutroSeconds = value }
            }
        )
    }

    private var playbackSpeedBinding: Binding<Float?> {
        Binding(
            get: { current.playbackSpeed },
            set: { value in
                store.updateFeedSettings(for: feedId) { $0.playbackSpeed = value }
            }
        )
    }

    private var episodeSortBinding: Binding<FeedEpisodeSort?> {
        Binding(
            get: { current.episodeSort },
            set: { value in
                store.updateFeedSettings(for: feedId) { $0.episodeSort = value }
            }
        )
    }

    private var episodeSortAccessibilityValue: String {
        current.episodeSort?.label ?? String(localized: "Use global")
    }

    private var episodeSortHelp: String {
        if let sort = current.episodeSort {
            return String(
                format: String(localized: "This podcast: %@. Feed detail Sort menu saves per podcast. itunes:type does not change sort."),
                sort.label
            )
        }
        let global = appSettings.feedEpisodeSort.label
        return String(
            format: String(localized: "Using global default (%@). Change here or via Feed detail Sort to override for this podcast only."),
            global
        )
    }

    private var skipIntroHelp: String {
        let global = AppSettings.skipIntroOutroLabel(appSettings.skipIntroSeconds)
        if let override = current.skipIntroSeconds {
            let label = AppSettings.skipIntroOutroLabel(override)
            return "This podcast uses \(label) instead of Settings → Skip intro (currently \(global))."
        }
        return "Follows Settings → Skip intro (currently \(global)). Applied on a fresh start (position ≈ 0)."
    }

    private var skipOutroHelp: String {
        let global = AppSettings.skipIntroOutroLabel(appSettings.skipOutroSeconds)
        if let override = current.skipOutroSeconds {
            let label = AppSettings.skipIntroOutroLabel(override)
            return "This podcast uses \(label) instead of Settings → Skip outro (currently \(global))."
        }
        return "Follows Settings → Skip outro (currently \(global)). Near end, remaining ≤ value finishes the episode."
    }

    private var playbackSpeedHelp: String {
        let global = PlaybackService.formatPlaybackSpeed(appSettings.defaultPlaybackSpeed)
        if let override = current.playbackSpeed {
            let label = PlaybackService.formatPlaybackSpeed(override)
            return String(
                format: String(localized: "This podcast starts at %@ instead of Settings → Default speed (currently %@). Applied on a fresh episode start for this feed."),
                label,
                global
            )
        }
        return String(
            format: String(localized: "Follows Settings → Default speed (currently %@). Applied when starting a fresh episode for this podcast."),
            global
        )
    }

    private var playbackSpeedAccessibilityValue: String {
        if let override = current.playbackSpeed {
            return PlaybackService.formatPlaybackSpeed(override)
        }
        return String(localized: "Use global")
    }
}
