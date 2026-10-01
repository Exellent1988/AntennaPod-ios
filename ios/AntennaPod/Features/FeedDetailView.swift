import SwiftUI
import UIKit

struct FeedDetailView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var downloads: DownloadService
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openURL) private var openURL
    let feed: PodcastFeed
    @State private var showPerFeedSettings = false
    @State private var showDownloadAllConfirm = false
    @State private var showMarkAllPlayedConfirm = false
    @State private var showUnsubscribeConfirm = false
    @State private var showFeedURLCopied = false
    @State private var showFeedDescription = false
    @Environment(\.dismiss) private var dismiss
    @State private var copyFeedURLFeedbackTick = 0
    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    /// Live feed from the store when available (episodes refresh after pull/refresh).
    private var liveFeed: PodcastFeed {
        store.feeds.first(where: { $0.id == feed.id }) ?? feed
    }

    private var feedTags: [String] {
        store.tags(for: liveFeed.id)
    }

    /// Channel description as plain text (HTML stripped). Empty → hide info toolbar control.
    private var plainFeedDescription: String {
        guard let raw = liveFeed.descriptionText else { return "" }
        return HTMLTextStripping.plainText(from: raw)
    }

    private var hasReadableFeedDescription: Bool {
        !plainFeedDescription.isEmpty
    }

    /// Episodes for this feed ordered by `AppSettings.feedEpisodeSort` (`pubDateEpochMs`).
    /// Missing dates sort last in both modes. Does not mutate stored feed order.
    private var sortedEpisodes: [PodcastEpisode] {
        liveFeed.episodes.sorted { lhs, rhs in
            switch settings.feedEpisodeSort {
            case .newestFirst:
                let l = lhs.pubDateEpochMs ?? Int64.min
                let r = rhs.pubDateEpochMs ?? Int64.min
                if l != r { return l > r }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .oldestFirst:
                let l = lhs.pubDateEpochMs ?? Int64.max
                let r = rhs.pubDateEpochMs ?? Int64.max
                if l != r { return l < r }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }

    /// Visible episodes: sort → chip filter → search.
    /// Chip via `AppSettings.feedEpisodeFilter` (`isPlayed`; Unplayed also excludes archived,
    /// same spirit as All Episodes Unplayed). Empty query shows the chip-filtered sorted list.
    /// Matches title and optional episode descriptionText (raw feed text / HTML).
    private var filteredEpisodes: [PodcastEpisode] {
        var base = sortedEpisodes
        switch settings.feedEpisodeFilter {
        case .all:
            break
        case .unplayed:
            // Same spirit as All Episodes Unplayed / Inbox: not played and not archived.
            base = base.filter { !store.isPlayed($0.id) && !store.isArchived($0.id) }
        case .played:
            base = base.filter { store.isPlayed($0.id) }
        }
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return base }
        return base.filter {
            $0.title.localizedCaseInsensitiveContains(q)
                || ($0.descriptionText?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    private var isFiltering: Bool {
        settings.feedEpisodeFilter != .all
            || !debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Unplayed, not archived, not downloaded — newest first, soft-capped.
    /// Bulk Download all always uses full-feed eligibility (not the filtered subset).
    private var downloadAllCandidates: [PodcastEpisode] {
        downloads.eligibleForFeedDownloadAll(in: liveFeed, store: store)
    }

    /// Unplayed, non-archived episodes on this feed only (for Mark all as played).
    /// Bulk Mark all as played always uses full-feed eligibility (not the filtered subset).
    private var markAllPlayedCandidates: [PodcastEpisode] {
        liveFeed.episodes.filter { !store.isPlayed($0.id) && !store.isArchived($0.id) }
    }

    var body: some View {
        List {
            if LocalFolderFeed.isLocalFolderFeed(liveFeed) {
                Section {
                    Label("Local folder feed", systemImage: "folder.fill")
                        .foregroundStyle(.orange)
                    Text("Episodes are audio files in a picked folder (mp3 / m4a / aac / wav / flac). No RSS and no network refresh — pull Refresh (swipe on Subscriptions) to re-scan. Unsubscribe releases folder access.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if !feedTags.isEmpty {
                Section("Tags") {
                    FlowTagRow(tags: feedTags)
                    Button("Manage tags…") {
                        showPerFeedSettings = true
                    }
                }
            }
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(FeedEpisodeFilter.allCases) { chip in
                            FeedEpisodeFilterChip(
                                title: chip.label,
                                selected: settings.feedEpisodeFilter == chip
                            ) {
                                settings.feedEpisodeFilter = chip
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }

            Section("Episodes") {
                if liveFeed.episodes.isEmpty {
                    ContentUnavailableView(
                        "No episodes",
                        systemImage: "list.bullet",
                        description: Text("This podcast has no episodes yet. Pull to refresh on Subscriptions.")
                    )
                } else if filteredEpisodes.isEmpty {
                    ContentUnavailableView(
                        "No matching episodes",
                        systemImage: "magnifyingglass",
                        description: Text(
                            isFiltering
                                ? String(localized: "No episodes match your filter.")
                                : String(localized: "No episodes match your search.")
                        )
                    )
                } else {
                    ForEach(filteredEpisodes) { episode in
                        EpisodeRow(episode: episode, feedTitle: liveFeed.title)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    store.togglePlayed(episode.id)
                                } label: {
                                    Label(
                                        store.isPlayed(episode.id)
                                            ? String(localized: "Mark unplayed")
                                            : String(localized: "Mark played"),
                                        systemImage: store.isPlayed(episode.id) ? "circle" : "checkmark.circle"
                                    )
                                }
                                .tint(.blue)
                                Button {
                                    store.toggleArchived(episode.id)
                                } label: {
                                    Label(
                                        store.isArchived(episode.id) ? "Restore" : "Archive",
                                        systemImage: store.isArchived(episode.id) ? "arrow.uturn.backward" : "archivebox"
                                    )
                                }
                                .tint(store.isArchived(episode.id) ? .green : .orange)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    store.playNext(episode, currentlyPlayingId: playback.currentEpisode?.id)
                                } label: {
                                    Label("Play Next", systemImage: "text.insert")
                                }
                                .tint(.teal)
                                Button {
                                    store.enqueue(episode)
                                } label: {
                                    Label("Queue", systemImage: "text.append")
                                }
                                .tint(.purple)
                                if let url = episode.shareURL(feed: liveFeed) {
                                    ShareLink(
                                        item: url,
                                        subject: Text(episode.title),
                                        message: Text(episode.shareMessage(feedTitle: liveFeed.title))
                                    ) {
                                        Label("Share", systemImage: "square.and.arrow.up")
                                    }
                                    .tint(.indigo)
                                    .accessibilityLabel(String(localized: "Share episode"))
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle(liveFeed.title)
        .searchable(text: $searchText, prompt: "Search episodes")
        .onChange(of: searchText) { _, newValue in
            scheduleFilter(for: newValue)
        }
        .onDisappear {
            debounceTask?.cancel()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker(selection: $settings.feedEpisodeSort) {
                        ForEach(FeedEpisodeSort.allCases) { sort in
                            Label(sort.label, systemImage: sort.systemImage)
                                .tag(sort)
                        }
                    } label: {
                        Text("Sort")
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort episodes")
            }
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    if hasReadableFeedDescription {
                        Button {
                            showFeedDescription = true
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .accessibilityLabel(String(localized: "Podcast description"))
                        .accessibilityHint(String(localized: "Opens the podcast description from the feed"))
                    }
                    if let url = liveFeed.shareURL {
                        ShareLink(
                            item: url,
                            subject: Text(liveFeed.title),
                            message: Text(liveFeed.title)
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share podcast")
                    }
                    Menu {
                        if let url = liveFeed.websiteURL {
                            Button {
                                openURL(url)
                            } label: {
                                Label("Open podcast website", systemImage: "safari")
                            }
                            .accessibilityLabel(String(localized: "Open podcast website"))
                            .accessibilityHint(String(localized: "Opens the podcast webpage in the system browser"))
                        }

                        Button {
                            copyFeedURL()
                        } label: {
                            Label("Copy feed URL", systemImage: "doc.on.doc")
                        }
                        .disabled(!canCopyFeedURL)
                        .accessibilityLabel(String(localized: "Copy feed URL"))

                        Button {
                            showDownloadAllConfirm = true
                        } label: {
                            Label("Download all", systemImage: "arrow.down.circle")
                        }
                        .disabled(downloadAllCandidates.isEmpty)

                        Button {
                            showMarkAllPlayedConfirm = true
                        } label: {
                            Label("Mark all as played", systemImage: "checkmark.circle")
                        }
                        .disabled(markAllPlayedCandidates.isEmpty)

                        Button(role: .destructive) {
                            showUnsubscribeConfirm = true
                        } label: {
                            Label("Unsubscribe", systemImage: "trash")
                        }
                    } label: {
                        Label("Feed actions", systemImage: "ellipsis.circle")
                    }
                    Button {
                        showPerFeedSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Podcast settings")
                }
            }
        }
        .confirmationDialog(
            "Download all?",
            isPresented: $showDownloadAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Download all") {
                let episodes = downloadAllCandidates
                Task {
                    await downloads.downloadAllManual(episodes)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Queues download of \(downloadAllCandidates.count) unplayed episodes (newest first, max \(DownloadService.feedDownloadAllCap)). Played, archived, and already downloaded are skipped. Manual download Wi‑Fi only still applies."
            )
        }
        .confirmationDialog(
            "Mark all as played?",
            isPresented: $showMarkAllPlayedConfirm,
            titleVisibility: .visible
        ) {
            Button("Mark all as played") {
                store.markAllPlayed(inFeedId: liveFeed.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Marks \(markAllPlayedCandidates.count) unplayed episodes in this podcast as played. Does not archive; auto-delete after playing still applies when enabled."
            )
        }
        .confirmationDialog(
            "Unsubscribe?",
            isPresented: $showUnsubscribeConfirm,
            titleVisibility: .visible
        ) {
            Button("Unsubscribe", role: .destructive) {
                store.unsubscribe(liveFeed)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Unsubscribe from \"\(liveFeed.title)\"? Removes this podcast from Subscriptions, its feed settings and tags, queue items from this feed, and favorites, archive, and playback history for its episodes. Downloaded files are kept."
            )
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showFeedURLCopied
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "Feed URL copied to the pasteboard."))
        }
        .sensoryFeedback(.success, trigger: copyFeedURLFeedbackTick)
        .sheet(isPresented: $showPerFeedSettings) {
            NavigationStack {
                PerFeedSettingsView(feedId: feed.id, feedTitle: liveFeed.title)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showPerFeedSettings = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showFeedDescription) {
            FeedDescriptionSheetView(feed: liveFeed)
        }
        .safeAreaInset(edge: .bottom) {
            if let error = downloads.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(.ultraThinMaterial)
            }
        }
    }


    /// Network RSS/Atom feeds only — local-folder feeds use a synthetic `local-folder://` id, not a pasteable feed URL.
    private var canCopyFeedURL: Bool {
        let trimmed = liveFeed.feedUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !LocalFolderFeed.isLocalFolderFeed(liveFeed)
    }

    private func copyFeedURL() {
        guard canCopyFeedURL else { return }
        let trimmed = liveFeed.feedUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        UIPasteboard.general.string = trimmed
        copyFeedURLFeedbackTick += 1
        showFeedURLCopied = true
    }

    private func scheduleFilter(for term: String) {
        debounceTask?.cancel()
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            debouncedQuery = ""
            return
        }
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: debounceNs)
            guard !Task.isCancelled else { return }
            debouncedQuery = trimmed
        }
    }
}



/// Filter chip for Feed detail All / Unplayed / Played (mirrors Downloads / All Episodes).
private struct FeedEpisodeFilterChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(String(localized: "Filters the Feed episodes list"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Simple wrapping tag chips (Feed detail header).
private struct FlowTagRow: View {
    let tags: [String]

    var body: some View {
        // LazyVGrid keeps layout simple without a custom flow layout.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
        }
    }
}

struct EpisodeRow: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var downloads: DownloadService
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openURL) private var openURL
    let episode: PodcastEpisode
    let feedTitle: String
    /// When set (e.g. History last-played), shown instead of the episode pub date.
    var dateOverride: Date? = nil
    var dateAccessibilityLabel: String? = nil

    @State private var showDescription = false
    @State private var showCopiedAlert = false
    @State private var copiedAlertMessage = ""
    @State private var copyURLFeedbackTick = 0

    private var state: EpisodePlaybackState {
        store.playbackState(for: episode.id)
    }

    /// Index in the persisted queue, or `nil` when not queued (drives Move to top/bottom visibility).
    private var queueIndex: Int? {
        store.queue.firstIndex(where: { $0.id == episode.id })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(episode.title)
                        .font(.headline)
                    Spacer(minLength: 8)
                    if store.isFavorite(episode.id) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                    }
                    if store.isArchived(episode.id) {
                        Image(systemName: "archivebox.fill")
                            .foregroundStyle(.orange)
                    }
                    if state.isPlayed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                if !feedTitle.isEmpty {
                    Text(feedTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if dateOverride != nil || episode.pubDateEpochMs != nil || formattedKnownDuration != nil {
                    HStack(spacing: 6) {
                        if let dateOverride {
                            Text(dateOverride, style: .relative)
                        } else if let ms = episode.pubDateEpochMs {
                            Text(Date(timeIntervalSince1970: Double(ms) / 1000), style: .date)
                        }
                        if let formattedKnownDuration {
                            if dateOverride != nil || episode.pubDateEpochMs != nil {
                                Text("·")
                                    .accessibilityHidden(true)
                            }
                            Text(formattedKnownDuration)
                                .monospacedDigit()
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if progressFraction > 0, !state.isPlayed {
                    ProgressView(value: progressFraction)
                        .tint(.accentColor)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(episodeAccessibilityLabel)
            .accessibilityAddTraits(.isStaticText)

            HStack {
                Button {
                    playback.play(episode: episode)
                } label: {
                    Label(resumeLabel, systemImage: "play.fill")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(resumeLabel)
                .accessibilityAddTraits(.startsMediaSession)

                Button {
                    Task { await downloads.download(episode) }
                } label: {
                    if downloads.inProgress.contains(episode.id) {
                        ProgressView()
                    } else if downloads.isDownloaded(episode) {
                        Label("Downloaded", systemImage: "checkmark.circle.fill")
                    } else {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(episode.downloadUrl == nil || downloads.inProgress.contains(episode.id))
                .accessibilityLabel(downloadAccessibilityLabel)

                Button {
                    store.enqueue(episode)
                } label: {
                    Label("Queue", systemImage: "text.append")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(String(localized: "Queue"))

                Button {
                    store.togglePlayed(episode.id)
                } label: {
                    Label(
                        state.isPlayed ? "Mark unplayed" : "Mark played",
                        systemImage: state.isPlayed ? "circle" : "checkmark.circle"
                    )
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(
                    state.isPlayed
                        ? String(localized: "Mark unplayed")
                        : String(localized: "Mark played")
                )
                .accessibilityHint(
                    state.isPlayed
                        ? String(localized: "Marks this episode as unplayed")
                        : String(localized: "Marks this episode as played")
                )

                Button {
                    store.toggleFavorite(episode.id)
                } label: {
                    Label(
                        store.isFavorite(episode.id) ? "Unfavorite" : "Favorite",
                        systemImage: store.isFavorite(episode.id) ? "star.fill" : "star"
                    )
                }
                .buttonStyle(.bordered)
                .tint(store.isFavorite(episode.id) ? .yellow : nil)
                .accessibilityLabel(
                    store.isFavorite(episode.id)
                        ? String(localized: "Remove from favorites")
                        : String(localized: "Add to favorites")
                )

                Button {
                    store.toggleArchived(episode.id)
                } label: {
                    Label(
                        store.isArchived(episode.id) ? "Restore" : "Archive",
                        systemImage: store.isArchived(episode.id) ? "archivebox.fill" : "archivebox"
                    )
                }
                .buttonStyle(.bordered)
                .tint(store.isArchived(episode.id) ? .orange : nil)
                .accessibilityLabel(
                    store.isArchived(episode.id)
                        ? String(localized: "Restore")
                        : String(localized: "Archive")
                )
                .accessibilityHint(
                    store.isArchived(episode.id)
                        ? String(localized: "Restores this episode from the archive")
                        : String(localized: "Hides this episode from Inbox without marking it played")
                )

                episodeShareControl
            }
            .labelStyle(.iconOnly)
        }
        .padding(.vertical, 4)
        .opacity(store.isArchived(episode.id) ? 0.55 : 1)
        .contextMenu {
            Button {
                playback.playFromBeginning(episode: episode)
            } label: {
                Label("Play from beginning", systemImage: "backward.end.fill")
            }
            .accessibilityLabel(String(localized: "Play from beginning"))
            .accessibilityHint(String(localized: "Loads this episode from the start and plays"))

            if let url = episode.websiteURL {
                Button {
                    openURL(url)
                } label: {
                    Label("Open episode website", systemImage: "safari")
                }
                .accessibilityLabel(String(localized: "Open episode website"))
                .accessibilityHint(String(localized: "Opens the episode webpage in the system browser"))

                Button {
                    copyEpisodeLink(url)
                } label: {
                    Label("Copy episode link", systemImage: "doc.on.doc")
                }
                .accessibilityLabel(String(localized: "Copy episode link"))
                .accessibilityHint(String(localized: "Copies the episode webpage URL to the pasteboard"))
            }
            if let url = episode.mediaURL {
                Button {
                    copyMediaURL(url)
                } label: {
                    Label("Copy media URL", systemImage: "link")
                }
                .accessibilityLabel(String(localized: "Copy media URL"))
                .accessibilityHint(String(localized: "Copies the episode media / enclosure URL to the pasteboard"))
            }
            if let url = episodeShareURL {
                ShareLink(
                    item: url,
                    subject: Text(episode.title),
                    message: Text(episodeShareMessage)
                ) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel(String(localized: "Share episode"))
            }
            Button {
                store.toggleFavorite(episode.id)
            } label: {
                Label(
                    store.isFavorite(episode.id) ? "Unfavorite" : "Favorite",
                    systemImage: store.isFavorite(episode.id) ? "star.slash" : "star"
                )
            }
            .accessibilityLabel(
                store.isFavorite(episode.id)
                    ? String(localized: "Remove from favorites")
                    : String(localized: "Add to favorites")
            )
            Button {
                store.toggleArchived(episode.id)
            } label: {
                Label(
                    store.isArchived(episode.id) ? "Restore" : "Archive",
                    systemImage: store.isArchived(episode.id) ? "arrow.uturn.backward" : "archivebox"
                )
            }
            Button {
                store.togglePlayed(episode.id)
            } label: {
                Label(
                    state.isPlayed ? "Mark unplayed" : "Mark played",
                    systemImage: state.isPlayed ? "circle" : "checkmark.circle"
                )
            }
            Button {
                store.playNext(episode, currentlyPlayingId: playback.currentEpisode?.id)
            } label: {
                Label("Play Next", systemImage: "text.insert")
            }
            Button {
                store.enqueue(episode)
            } label: {
                Label("Add to queue", systemImage: "text.append")
            }
            // Move to top/bottom = manual reorder; hidden when Queue lock is on (Play Next / enqueue stay).
            if let qi = queueIndex, !settings.queueLocked {
                if qi > 0 {
                    Button {
                        store.moveQueueItemToTop(episode)
                    } label: {
                        Label("Move to top", systemImage: "arrow.up.to.line")
                    }
                    .accessibilityLabel(String(localized: "Move to top"))
                    .accessibilityHint(String(localized: "Places this episode at the start of the queue"))
                }
                if qi < store.queue.count - 1 {
                    Button {
                        store.moveQueueItemToBottom(episode)
                    } label: {
                        Label("Move to bottom", systemImage: "arrow.down.to.line")
                    }
                    .accessibilityLabel(String(localized: "Move to bottom"))
                    .accessibilityHint(String(localized: "Places this episode at the end of the queue"))
                }
            }
            Button {
                showDescription = true
            } label: {
                Label("Shownotes", systemImage: "doc.text")
            }
        }
        .sheet(isPresented: $showDescription) {
            EpisodeDescriptionSheetView(episode: episode, feedTitle: feedTitle)
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showCopiedAlert
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(copiedAlertMessage)
        }
        .sensoryFeedback(.success, trigger: copyURLFeedbackTick)
    }

    private func copyEpisodeLink(_ url: URL) {
        UIPasteboard.general.string = url.absoluteString
        copiedAlertMessage = String(localized: "Episode link copied to the pasteboard.")
        copyURLFeedbackTick += 1
        showCopiedAlert = true
    }

    private func copyMediaURL(_ url: URL) {
        UIPasteboard.general.string = url.absoluteString
        copiedAlertMessage = String(localized: "Media URL copied to the pasteboard.")
        copyURLFeedbackTick += 1
        showCopiedAlert = true
    }

    private var resolvedFeed: PodcastFeed? {
        store.feed(containingEpisodeId: episode.id)
    }

    private var episodeShareURL: URL? {
        episode.shareURL(feed: resolvedFeed)
    }

    private var episodeShareMessage: String {
        episode.shareMessage(feedTitle: feedTitle.isEmpty ? resolvedFeed?.title : feedTitle)
    }

    @ViewBuilder
    private var episodeShareControl: some View {
        if let url = episodeShareURL {
            ShareLink(
                item: url,
                subject: Text(episode.title),
                message: Text(episodeShareMessage)
            ) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(String(localized: "Share episode"))
            .accessibilityHint(String(localized: "Opens the system share sheet with the episode title and link"))
        } else {
            Button {} label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .disabled(true)
            .accessibilityLabel(String(localized: "Share episode"))
            .accessibilityHint(String(localized: "No shareable link for this episode"))
        }
    }

    private var progressFraction: Double {
        let duration = state.durationSeconds
        let position = state.positionSeconds
        guard duration.isFinite, duration > 0, position > 0 else {
            return 0
        }
        return min(1, position / duration)
    }

    private var resumeLabel: String {
        if !state.isPlayed, state.positionSeconds > 1 {
            return String(localized: "Resume")
        }
        return String(localized: "Play")
    }

    private var downloadAccessibilityLabel: String {
        if downloads.inProgress.contains(episode.id) {
            return String(localized: "Downloading")
        }
        if downloads.isDownloaded(episode) {
            return String(localized: "Downloaded")
        }
        return String(localized: "Download")
    }

    /// VoiceOver summary: title, feed, duration, played/progress, downloaded (+ favorite/archived).
    private var episodeAccessibilityLabel: String {
        var parts: [String] = [episode.title]
        if !feedTitle.isEmpty {
            parts.append(feedTitle)
        }
        if let dateOverride, let custom = dateAccessibilityLabel {
            parts.append(custom)
        }
        if let formattedKnownDuration {
            parts.append(String(localized: "Duration \(formattedKnownDuration)"))
        }
        if state.isPlayed {
            parts.append(String(localized: "Played"))
        } else if progressFraction > 0 {
            let pct = Int((progressFraction * 100).rounded())
            parts.append("\(pct) percent played")
        }
        if downloads.isDownloaded(episode) {
            parts.append(String(localized: "Downloaded"))
        } else if downloads.inProgress.contains(episode.id) {
            parts.append(String(localized: "Downloading"))
        }
        if store.isFavorite(episode.id) {
            parts.append(String(localized: "Favorite"))
        }
        if store.isArchived(episode.id) {
            parts.append(String(localized: "Archived"))
        }
        return parts.joined(separator: ", ")
    }

    /// Prefer feed `itunes:duration` / media duration; fall back to saved playback duration.
    /// Hidden when both unknown or zero — never invents a length.
    private var knownDurationSeconds: Double? {
        if episode.hasKnownDuration {
            return episode.durationSeconds
        }
        let played = state.durationSeconds
        if played.isFinite, played > 0 {
            return played
        }
        return nil
    }

    /// `m:ss` / `h:mm:ss` via the same formatter as the full-player scrubber / share timestamp.
    private var formattedKnownDuration: String? {
        PodcastEpisode.formatPlaybackPosition(knownDurationSeconds)
    }
}
