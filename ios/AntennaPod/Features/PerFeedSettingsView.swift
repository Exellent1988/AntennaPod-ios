import SwiftUI

/// Per-subscription overrides (Display name / Private note / Keep at top / Auto-download / Auto-delete after play / Keep updated / New episodes / Notifications / Skip intro·outro / Speed / Episode sort) + HTTP Basic auth (Keychain) + tags.
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
    @State private var authUsername = ""
    @State private var authPasswordDraft = ""
    @State private var authSaved = false
    @State private var authStatusMessage: String?
    @State private var authErrorMessage: String?
    @State private var privateNoteDraft = ""
    @State private var displayNameDraft = ""

    private var liveFeed: PodcastFeed? {
        store.feeds.first { $0.id == feedId }
    }

    private var isLocalFolderFeed: Bool {
        guard let feed = liveFeed else { return false }
        return LocalFolderFeed.isLocalFolderFeed(feed)
    }

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
                TextField(String(localized: "Display name"), text: $displayNameDraft)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .accessibilityLabel(String(localized: "Display name"))
                    .accessibilityHint(String(localized: "Optional local nickname for this podcast. Leave empty to use the feed title from RSS."))
                    .accessibilityValue(current.customTitle ?? String(localized: "Using feed title"))
                    .onChange(of: displayNameDraft) { _, newValue in
                        commitDisplayNameDraft(newValue)
                    }
                if current.customTitle != nil {
                    Button(String(localized: "Reset display name")) {
                        displayNameDraft = ""
                        store.updateFeedSettings(for: feedId) { $0.customTitle = nil }
                    }
                    .accessibilityLabel(String(localized: "Reset display name"))
                    .accessibilityHint(String(localized: "Clears the local nickname immediately and shows the feed title from RSS again. No confirmation. Local only — does not change the RSS title, tags, pin, private note, or subscriptions."))
                }
                if let rss = liveFeed?.title, !rss.isEmpty, current.customTitle != nil {
                    Text(String(localized: "Feed title: \(rss)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(String(localized: "Feed title: \(rss)"))
                }
            } header: {
                Text(String(localized: "Display name"))
            } footer: {
                Text(String(localized: "Local only — does not rename the RSS title on this device’s feed object. Survives refresh; cleared when you unsubscribe."))
            }

            Section {
                TextEditor(text: $privateNoteDraft)
                    .frame(minHeight: 88)
                    .accessibilityLabel(String(localized: "Private note"))
                    .accessibilityHint(String(localized: "Optional local-only note for this podcast. Not synced and not from the feed. Maximum 1000 characters."))
                    .accessibilityValue(
                        privateNoteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? String(localized: "Empty")
                            : privateNoteDraft
                    )
                    .onChange(of: privateNoteDraft) { _, newValue in
                        commitPrivateNoteDraft(newValue)
                    }
                if current.privateNote != nil || !privateNoteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(String(localized: "Clear private note")) {
                        privateNoteDraft = ""
                        store.updateFeedSettings(for: feedId) { $0.privateNote = nil }
                    }
                    .accessibilityLabel(String(localized: "Clear private note"))
                    .accessibilityHint(String(localized: "Removes the local private note for this podcast immediately. No confirmation. Local only — not RSS / gpodder / OPML. Does not affect episode private notes, bookmarks, pin, tags, favorites, or the queue."))
                }
                Text(
                    String(
                        format: String(localized: "%lld / %lld characters"),
                        Int64(min(privateNoteDraft.count, FeedSettings.privateNoteMaxLength)),
                        Int64(FeedSettings.privateNoteMaxLength)
                    )
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityLabel(
                    String(
                        format: String(localized: "%lld of %lld characters used"),
                        Int64(min(privateNoteDraft.count, FeedSettings.privateNoteMaxLength)),
                        Int64(FeedSettings.privateNoteMaxLength)
                    )
                )
            } header: {
                Text(String(localized: "Private note"))
            } footer: {
                Text(String(localized: "Local only on this device — not from RSS, not synced to gpodder, and not written to OPML or HTML export. Distinct from episode private notes and bookmarks. Included in iOS JSON backup with other feed settings. Survives refresh; cleared when you unsubscribe. Maximum 1000 characters."))
            }

            Section {
                Toggle(isOn: isPinnedBinding) {
                    Label(String(localized: "Keep at top"), systemImage: "pin.fill")
                }
                .accessibilityLabel(String(localized: "Keep at top"))
                .accessibilityHint(String(localized: "Pins this podcast above unpinned ones on the Subscriptions list for every sort. Local preference only — not synced."))
                .accessibilityValue(
                    current.isPinned
                        ? String(localized: "On")
                        : String(localized: "Off")
                )
            } header: {
                Text(String(localized: "Subscriptions list"))
            } footer: {
                Text(String(localized: "When on, this podcast stays above unpinned podcasts on Subscriptions for every sort (Recently updated, Alphabetical, …). Local preference only — not a separate sort mode; not synced to gpodder; cleared when you unsubscribe. Included in iOS JSON backup with other feed settings."))
            }

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
                .accessibilityHint(String(localized: "When Never, Refresh all, pull-to-refresh, and timed refresh skip this podcast. Manual single-podcast refresh still works."))
                .accessibilityValue(current.keepUpdated.label)
                Text(keepUpdatedHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(keepUpdatedHelp)
            } header: {
                Text("Refresh")
            } footer: {
                Text("Refresh all, pull-to-refresh (Subscriptions, Home, Inbox), and timed Keep updated refresh skip Never. Manual single-podcast refresh (swipe or Feed detail) still works.")
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
                        Text(option.notifyLabel).tag(option)
                    }
                }
                .accessibilityLabel(String(localized: "Notify on new episodes"))
                .accessibilityValue(notifyAccessibilityValue)
                .accessibilityHint(String(localized: "Use global, On, or Off. Global Settings → Notify on new episodes is the master switch. Per-podcast Off silences this podcast when global is on; per-podcast On is ignored while global is off. Local notifications only — no push."))
                Text(notifyHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(notifyHelp)
            } header: {
                Text("Notifications")
            } footer: {
                Text(String(localized: "Global Notify on new episodes is the master switch. Per-podcast On is ignored while global is off; per-podcast Off silences that feed when global is on. Local UserNotifications only — no push / APNs."))
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
                .accessibilityHint(String(localized: "Use global, Newest first, Oldest first, Shortest first, Longest first, Title A–Z, or Title Z–A for this podcast’s episode list. Serial may auto-set Oldest first once when unset; capsule stays display-only."))
                .accessibilityValue(episodeSortAccessibilityValue)
                Text(episodeSortHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(episodeSortHelp)
                if liveFeed?.isItunesTypeSerial == true {
                    Text(String(localized: "Serial podcasts may use Oldest first once for narrative order when per-feed sort is unset. You can still pick any sort. The itunes:type capsule stays display-only."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(String(localized: "Serial podcasts may use Oldest first once for narrative order when per-feed sort is unset. You can still pick any sort. The itunes:type capsule stays display-only."))
                }
            } header: {
                Text("Episodes")
            }

            if !isLocalFolderFeed {
                Section {
                    TextField("Username", text: $authUsername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                        .accessibilityLabel(String(localized: "Username"))
                        .accessibilityHint(String(localized: "HTTP Basic username for this private podcast feed"))

                    if authSaved && authPasswordDraft.isEmpty {
                        LabeledContent("Password") {
                            Text("Stored in Keychain")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel(String(localized: "Password"))
                        .accessibilityValue(String(localized: "Stored in Keychain"))
                        SecureField("Replace password", text: $authPasswordDraft)
                            .textContentType(.password)
                            .accessibilityLabel(String(localized: "Replace password"))
                            .accessibilityHint(String(localized: "Leave blank to keep the Keychain password; enter a new password to replace it on Save"))
                    } else {
                        SecureField("Password", text: $authPasswordDraft)
                            .textContentType(.password)
                            .accessibilityLabel(String(localized: "Password"))
                            .accessibilityHint(String(localized: "Stored in the Keychain on Save — never in feed-settings.json or backup"))
                    }

                    if let authStatusMessage {
                        Text(authStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(authStatusMessage)
                    }
                    if let authErrorMessage {
                        Text(authErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityLabel(authErrorMessage)
                    }

                    Button("Save authentication") {
                        saveHttpBasicAuth()
                    }
                    .disabled(authUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityHint(String(localized: "Stores username and password in the Keychain for this podcast immediately. No confirmation. Enables private feed refresh and matching-host downloads for this podcast. Does not affect other podcasts, Podcast Index keys, subscriptions, or offline files."))

                    if authSaved {
                        Button("Clear authentication", role: .destructive) {
                            clearHttpBasicAuth()
                        }
                        .accessibilityHint(String(localized: "Removes HTTP Basic credentials for this podcast from the Keychain immediately. No confirmation. Private feed refresh and matching-host downloads for this podcast stop authenticating until you save again. Does not affect other podcasts, Podcast Index keys, subscriptions, or offline files."))
                    }
                } header: {
                    Text("Authentication")
                } footer: {
                    Text(authFooter)
                }
            }

            Section {
                if assignedTags.isEmpty {
                    Text(String(localized: "No tags yet"))
                        .foregroundStyle(.secondary)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(String(localized: "No tags yet"))
                        .accessibilityValue(perFeedNoTagsEmptyStateAccessibilityValue)
                        .accessibilityHint(
                            String(localized: "Add a new tag below, or tap a suggested tag if any appear. Tags filter Subscriptions.")
                        )
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
                        .accessibilityLabel(tag)
                        .accessibilityHint(String(localized: "Adds this existing tag to this podcast."))
                    }
                }

                HStack {
                    TextField("New tag", text: $newTagDraft)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .accessibilityLabel(String(localized: "New tag"))
                        .accessibilityHint(String(localized: "Type a new tag name for this podcast, then Add. Empty or whitespace-only names are ignored."))
                        .accessibilityValue(
                            FeedTags.normalize(newTagDraft) == nil
                                ? String(localized: "Empty")
                                : (FeedTags.normalize(newTagDraft) ?? newTagDraft)
                        )
                        .onSubmit(addDraftTag)
                    Button("Add") { addDraftTag() }
                        .disabled(FeedTags.normalize(newTagDraft) == nil)
                        .accessibilityLabel(String(localized: "Add tag"))
                        .accessibilityHint(
                            FeedTags.normalize(newTagDraft) == nil
                                ? String(localized: "Enter a non-empty tag name to enable Add.")
                                : String(localized: "Assigns the new tag name to this podcast.")
                        )
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
                        privateNoteDraft = ""
                        displayNameDraft = ""
                    }
                }
            }
        }
        .navigationTitle(feedTitle.isEmpty ? String(localized: "Podcast settings") : feedTitle)
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
            .accessibilityHint(String(localized: "Removes this tag from all podcasts. Does not unsubscribe or delete downloads."))
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
        .onAppear {
            loadHttpBasicAuthState()
            privateNoteDraft = current.privateNote ?? ""
            displayNameDraft = current.customTitle ?? ""
        }
    }

    /// Cap draft length while typing; persist trimmed note (empty → nil).
    private func commitPrivateNoteDraft(_ newValue: String) {
        var draft = newValue
        if draft.count > FeedSettings.privateNoteMaxLength {
            let end = draft.index(draft.startIndex, offsetBy: FeedSettings.privateNoteMaxLength)
            draft = String(draft[..<end])
            if draft != privateNoteDraft {
                privateNoteDraft = draft
            }
        }
        let normalized = FeedSettings.normalizedPrivateNote(draft)
        if current.privateNote != normalized {
            store.updateFeedSettings(for: feedId) { $0.privateNote = normalized }
        }
    }

    /// The field keeps what is typed. Reading the trimmed saved title back into it
    /// removed each space as soon as it was typed at the end ("My " became "My").
    private func commitDisplayNameDraft(_ newValue: String) {
        if newValue.count > FeedSettings.customTitleMaxLength {
            let end = newValue.index(newValue.startIndex, offsetBy: FeedSettings.customTitleMaxLength)
            displayNameDraft = String(newValue[..<end])
            return
        }
        let normalized = FeedSettings.normalizedCustomTitle(newValue)
        if current.customTitle != normalized {
            store.updateFeedSettings(for: feedId) { $0.customTitle = normalized }
        }
    }

    private var authFooter: String {
        String(localized: "HTTP Basic for private feeds. Credentials are stored only in the Keychain on this device — never in feed-settings.json, OPML, or iOS JSON backup. Applied on feed refresh and on media downloads when the media host matches the feed host. Not used for local folder podcasts. Streaming without download may still fail if the player cannot send Authorization. Passwords are never logged.")
    }

    private func loadHttpBasicAuthState() {
        authErrorMessage = nil
        authStatusMessage = nil
        authPasswordDraft = ""
        if let creds = FeedHttpBasicAuthKeychain.load(for: feedId), creds.isUsable {
            authUsername = creds.trimmedUsername
            authSaved = true
        } else {
            authUsername = ""
            authSaved = false
        }
    }

    private func saveHttpBasicAuth() {
        authErrorMessage = nil
        authStatusMessage = nil
        let user = authUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty else {
            authErrorMessage = String(localized: "Username is required for HTTP authentication")
            return
        }
        // Keep existing password when Replace field left blank and credentials already saved.
        let password: String
        if authPasswordDraft.isEmpty, authSaved,
           let existing = FeedHttpBasicAuthKeychain.load(for: feedId) {
            password = existing.password
        } else {
            password = authPasswordDraft
        }
        do {
            try FeedHttpBasicAuthKeychain.save(username: user, password: password, for: feedId)
            authSaved = true
            authPasswordDraft = ""
            authStatusMessage = String(localized: "Authentication saved in Keychain")
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }

    private func clearHttpBasicAuth() {
        FeedHttpBasicAuthKeychain.delete(for: feedId)
        authUsername = ""
        authPasswordDraft = ""
        authSaved = false
        authErrorMessage = nil
        authStatusMessage = String(localized: "Authentication cleared from Keychain")
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

    private var isPinnedBinding: Binding<Bool> {
        Binding(
            get: { current.isPinned },
            set: { value in
                store.setPinned(feedId: feedId, value)
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

    private var perFeedNoTagsEmptyStateAccessibilityValue: String {
        String(localized: "This podcast has no tags assigned. Tags are local labels for Subscriptions filters — not folders synced to gpodder.")
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
            return String(localized: "Follows Settings → New episodes (currently \(global)). Queue+download is only available as the global choice.")
        case .inboxOnly:
            return String(localized: "New episodes for this podcast stay in Inbox only — not added to Queue, even when global adds to Queue.")
        case .addToQueue:
            return String(localized: "Newly appeared episodes for this podcast are added to Queue (no auto-download from this override). Inbox still lists them while unplayed.")
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
            return String(localized: "Never auto-download this podcast, even when global Auto-download is on. New episodes Add to Queue and download still enqueues but does not download. Manual Download still works.")
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
            return String(localized: "Always delete this podcast’s offline file when an episode is marked played, even when the global toggle is off. Favorites still keep their offline files. Defers while that local file is the active player item.")
        case .never:
            return String(localized: "Never auto-delete this podcast’s offline files after playing, even when the global toggle is on. Manual Delete download still works.")
        }
    }

    private var keepUpdatedHelp: String {
        switch current.keepUpdated {
        case .useGlobal, .always:
            return String(localized: "Included in Refresh all, pull-to-refresh (Subscriptions, Home, Inbox), and timed Keep updated refresh (Subscriptions toolbar, launch/foreground interval). “Always” matches Use global until a global exclude exists.")
        case .never:
            return String(localized: "Skipped by Refresh all, pull-to-refresh (Subscriptions, Home, Inbox), and timed Keep updated refresh. You can still refresh this podcast alone from Subscriptions (swipe) or Feed detail.")
        }
    }

    private var notifyHelp: String {
        let global = appSettings.notifyOnNewEpisodes ? String(localized: "on") : String(localized: "off")
        switch current.notifyOnNewEpisodes {
        case .useGlobal:
            return String(localized: "Follows Settings → Notify on new episodes (currently \(global)). Global is the master switch. System permission still required. Local only — no push.")
        case .always:
            return String(localized: "On for this podcast only while Settings → Notify on new episodes is on (currently \(global)). Global is master — On does nothing while global is off. System permission still required. Local only — no push.")
        case .never:
            return String(localized: "Off for this podcast — no local notification, even when Settings → Notify on new episodes is on (currently \(global)). Local only — no push.")
        }
    }

    /// VoiceOver value: picker label plus whether global master actually allows banners for this feed.
    private var notifyAccessibilityValue: String {
        let globalOn = appSettings.notifyOnNewEpisodes
        switch current.notifyOnNewEpisodes {
        case .useGlobal:
            if globalOn {
                return String(localized: "Use global. Global Notify on new episodes is on, so this podcast may notify after refresh. System permission still required. Local only — no push.")
            }
            return String(localized: "Use global. Global Notify on new episodes is off, so this podcast does not notify. Local only — no push.")
        case .always:
            if globalOn {
                return String(localized: "On. Global Notify on new episodes is on, so this podcast may notify after refresh. System permission still required. Local only — no push.")
            }
            return String(localized: "On. Global Notify on new episodes is off, so On does nothing and this podcast does not notify. Local only — no push.")
        case .never:
            return String(localized: "Off. This podcast does not notify, even when Global Notify on new episodes is on. Local only — no push.")
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
                format: String(localized: "This podcast: %@. Feed detail Sort menu saves per podcast. Serial may auto-set Oldest first once when unset; capsule stays display-only."),
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
            return String(
                format: String(localized: "This podcast uses %@ instead of Settings → Skip intro (currently %@)."),
                label,
                global
            )
        }
        return String(
            format: String(localized: "Follows Settings → Skip intro (currently %@). Applied on a fresh start (position ≈ 0)."),
            global
        )
    }

    private var skipOutroHelp: String {
        let global = AppSettings.skipIntroOutroLabel(appSettings.skipOutroSeconds)
        if let override = current.skipOutroSeconds {
            let label = AppSettings.skipIntroOutroLabel(override)
            return String(
                format: String(localized: "This podcast uses %@ instead of Settings → Skip outro (currently %@)."),
                label,
                global
            )
        }
        return String(
            format: String(localized: "Follows Settings → Skip outro (currently %@). Near end, remaining ≤ value finishes the episode."),
            global
        )
    }

    private var playbackSpeedHelp: String {
        let global = PlaybackService.formatPlaybackSpeed(appSettings.defaultPlaybackSpeed)
        if let override = current.playbackSpeed {
            let label = PlaybackService.formatPlaybackSpeed(override)
            return String(
                format: String(localized: "This podcast starts at %@ instead of Settings → Default speed (currently %@). Applied on a fresh episode start and when you change this setting while an episode from this podcast is playing. Player speed controls stay session-only."),
                label,
                global
            )
        }
        return String(
            format: String(localized: "Follows Settings → Default speed (currently %@). Applied on a fresh episode start and when you change this setting while an episode from this podcast is playing. Player speed controls stay session-only."),
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
