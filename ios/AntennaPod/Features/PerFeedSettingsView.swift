import SwiftUI

/// Per-subscription overrides (Auto-download / Keep updated / New episodes / Notifications) + tags.
struct PerFeedSettingsView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var appSettings: AppSettings

    let feedId: UUID
    let feedTitle: String

    @State private var newTagDraft = ""
    @State private var renameFrom: String?
    @State private var renameDraft = ""
    @State private var showRenameAlert = false

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
            } header: {
                Text("Downloads")
            }

            Section {
                Picker("Keep updated", selection: keepUpdatedBinding) {
                    ForEach(PerFeedOverride.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                Text(keepUpdatedHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Refresh")
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
                                store.deleteTag(tag)
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
            Button("Cancel", role: .cancel) {
                renameFrom = nil
            }
            Button("Rename") {
                if let from = renameFrom {
                    store.renameTag(from: from, to: renameDraft)
                }
                renameFrom = nil
            }
        } message: {
            Text("Renames this tag on every podcast that uses it. Clear the name to delete it everywhere.")
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
        let global = appSettings.autoDownloadEnabled ? "on" : "off"
        switch current.autoDownload {
        case .useGlobal:
            return "Follows Settings → Auto-download (currently \(global)). Cap and Wi‑Fi-only still apply globally."
        case .always:
            return "Always enqueue after refresh for this podcast, even when global Auto-download is off. Cap and Wi‑Fi-only still apply."
        case .never:
            return "Never auto-download this podcast, even when global Auto-download is on. Manual Download still works."
        }
    }

    private var keepUpdatedHelp: String {
        switch current.keepUpdated {
        case .useGlobal, .always:
            return "Included when refreshing all feeds (Inbox pull-to-refresh, Keep updated interval, Home refresh). “Always” matches Use global until a global exclude exists."
        case .never:
            return "Skipped during refresh-all. You can still refresh this podcast alone from Subscriptions (swipe) or Add."
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
}
