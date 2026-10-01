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
    @State private var showEnqueueAllConfirm = false
    @State private var showUnsubscribeConfirm = false
    @State private var showFeedURLCopied = false
    @State private var showPodcastGuidCopied = false
    @State private var showFeedDescription = false
    @Environment(\.dismiss) private var dismiss
    @State private var copyFeedURLFeedbackTick = 0
    @State private var copyPodcastGuidFeedbackTick = 0
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

    /// Channel author when the feed provided it (hidden when missing — never invent).
    private var displayAuthor: String? {
        liveFeed.displayAuthor
    }

    /// Localized language name (or raw code) when the feed provided a language — hidden when missing.
    private var displayLanguage: String? {
        liveFeed.displayLanguage
    }

    /// itunes:category texts when the feed provided them — empty → hide (never invent taxonomy).
    private var displayCategories: [String] {
        liveFeed.displayCategories
    }

    /// Channel podcast:person when the feed provided them — empty → hide (never invent people).
    private var displayPeople: [PodcastPerson] {
        liveFeed.displayPeople
    }

    /// Channel podcast:location when the feed provided them — empty → hide (never invent / never geocode).
    private var displayLocations: [PodcastLocation] {
        liveFeed.displayLocations
    }

    /// Channel podcast:socialInteract when the feed provided openable http(s) — empty → hide (never invent).
    private var displaySocialInteracts: [PodcastSocialInteract] {
        liveFeed.displaySocialInteracts
    }

    /// Channel podcast:value recipients when the feed provided them — empty → hide (display-only; no payments).
    private var displayValues: [PodcastValue] {
        liveFeed.values
    }

    private var hasDisplayValueRecipients: Bool {
        !liveFeed.displayValueRecipients.isEmpty
    }

    /// Most recent channel podcast:trailer when the feed provided one — hide when missing (never invent).
    /// Distinct from item itunes:episodeType=trailer (EpisodeRow badge).
    private var displayTrailer: PodcastTrailer? {
        liveFeed.displayTrailer
    }

    /// Channel podcast:liveItem when the feed provided them — empty → hide (display-only; no live player).
    private var displayLiveItems: [PodcastLiveItem] {
        liveFeed.displayLiveItems
    }

    /// Podcast Index `podcast:guid` when the feed provided it — hide when missing (never invent).
    private var displayPodcastGuid: String? {
        liveFeed.displayPodcastGuid
    }

    /// VoiceOver for podcast:locked=yes badge + honest footnote (+ optional owner from feed).
    private var feedLockedAccessibilityLabel: String {
        var parts = [
            String(localized: "Locked"),
            String(localized: "This feed claims to be locked for transfer. This app does not verify ownership.")
        ]
        if let owner = liveFeed.displayLockedOwner {
            parts.append(String(localized: "Locked owner \(owner)"))
        }
        return parts.joined(separator: ". ")
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

    /// AntennaPod-like info bar: episode count + remaining over the **visible** Feed detail list
    /// (sort → chip → searchable). Remaining per episode = `max(0, duration − position)` when
    /// duration known; unplayed with duration contributes full duration; **played** (not current)
    /// → 0; **unknown duration skipped** (tilde when any skipped). Currently playing uses live
    /// `PlaybackService` position/duration. Wall-clock only (no playback-speed divide).
    /// Distinct from **Download all** / **Mark all as played** / **Add all to queue** full-feed eligibility counts.
    private var feedRemainingInfoLabel: String? {
        guard !filteredEpisodes.isEmpty else { return nil }
        return EpisodeRemainingTime.episodesInfoBarLabel(for: feedRemainingSummary)
    }

    private var feedRemainingAccessibilityLabel: String {
        guard let label = feedRemainingInfoLabel else { return "" }
        var parts = [String(localized: "Feed remaining time \(label)")]
        let unknown = feedRemainingSummary.unknownCount
        if unknown > 0 {
            parts.append(String(localized: "Remaining time excludes \(unknown) episode(s) with unknown duration"))
        }
        return parts.joined(separator: ". ")
    }

    private var feedRemainingSummary: EpisodeRemainingTime.Summary {
        EpisodeRemainingTime.summarize(
            episodes: filteredEpisodes,
            currentEpisodeId: playback.currentEpisode?.id,
            liveDurationSeconds: playback.durationSeconds,
            livePositionSeconds: playback.positionSeconds,
            isPlayed: { store.isPlayed($0) },
            savedDurationSeconds: { store.playbackState(for: $0).durationSeconds },
            savedPositionSeconds: { store.positionSeconds(for: $0) }
        )
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

    /// Full feed episode catalog minus already queued — Add all to queue always uses this,
    /// **not** the chip/search filtered visible list (`filteredEpisodes`). Same full-feed
    /// honesty as Download all / Mark all as played (eligibility not limited to visible filter).
    /// Confirm count and `enqueueAllFromFeed` share this eligibility (played/archived included).
    private var enqueueAllFromFeedCandidatesCount: Int {
        liveFeed.episodes.filter { !store.isInQueue($0.id) }.count
    }

    /// Completed Downloads catalog rows for this feed’s episode ids (same set as
    /// `DownloadService.deleteDownloads(forFeed:)`). Not chip/search filtered.
    private var unsubscribeFeedDownloadsCount: Int {
        downloads.downloads(forFeed: liveFeed).count
    }

    private var unsubscribeFeedDownloadsSizeLabel: String {
        DownloadStorageUsage.formatBytes(downloads.downloadsByteSize(forFeed: liveFeed))
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
            if let author = displayAuthor {
                Section {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(String(localized: "Author \(author)"))
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Feed language when present (itunes:language / RSS language / xml:lang); hide when missing.
            if let language = displayLanguage {
                Section {
                    Text(language)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(String(localized: "Language \(language)"))
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Channel itunes:explicit only — hide when feed does not mark explicit (never invent).
            if liveFeed.isExplicit {
                Section {
                    Text(String(localized: "Explicit"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.2), in: Capsule())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(String(localized: "Explicit"))
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Channel podcast:locked=yes only — display-only claim; no owner verification / host block.
            if liveFeed.isLocked {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Locked"))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.2), in: Capsule())
                        Text(String(localized: "This feed claims to be locked for transfer. This app does not verify ownership."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let owner = liveFeed.displayLockedOwner {
                            Text(String(localized: "Locked owner \(owner)"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(feedLockedAccessibilityLabel)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Channel podcast:guid when present — display/copy only; never invent; distinct from episode guid.
            if let guid = displayPodcastGuid {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Podcast GUID"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(guid)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Button {
                            copyPodcastGuid()
                        } label: {
                            Label("Copy podcast GUID", systemImage: "doc.on.doc")
                                .font(.subheadline)
                        }
                        .accessibilityLabel(String(localized: "Copy podcast GUID"))
                        .accessibilityHint(String(localized: "Copies the podcast GUID from the feed to the pasteboard"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .contain)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Feed itunes:category chips (parent + nested text attrs); hide when none — never invent.
            if !displayCategories.isEmpty {
                Section {
                    FeedCategoryChips(categories: displayCategories)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            String(localized: "Categories \(displayCategories.joined(separator: ", "))")
                        )
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Channel podcast:person — name + role when set; http(s) href → system browser; hide when none.
            if !displayPeople.isEmpty {
                Section {
                    PodcastPeopleListView(people: displayPeople)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Channel podcast:location — name + optional rel/osm; Open in Maps when geo lat,lon; hide when none.
            // Feed-provided only — never invent names / never geocode.
            if !displayLocations.isEmpty {
                Section {
                    PodcastLocationsListView(locations: displayLocations)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Channel podcast:socialInteract — Discuss opens http(s) uri in system browser; hide when none / disabled.
            // Feed-provided only — never invent URLs; no in-app Fediverse client / posting.
            if !displaySocialInteracts.isEmpty {
                Section {
                    PodcastSocialInteractListView(socialInteracts: displaySocialInteracts)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Channel podcast:value / valueRecipient — Value / Support creators metadata; display-only (no Lightning sends).
            // http(s) address → Open in browser; else Copy. Hide when none — never invent recipients / payment addresses.
            if hasDisplayValueRecipients {
                Section {
                    PodcastValueRecipientsListView(values: displayValues)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Channel podcast:trailer — title + Play (enclosure-like http(s) via PlaybackService) or Open URL; hide when none.
            // Distinct from itunes:episodeType=trailer on items (EpisodeRow Trailer badge).
            if let trailer = displayTrailer {
                Section {
                    feedTrailerRow(trailer)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            // Channel podcast:liveItem — status/start/end/title + Open link/contentLink in browser; hide when none.
            // Display-only — no live stream player / recording / chat / payments. Never invent live items.
            if !displayLiveItems.isEmpty {
                Section {
                    PodcastLiveItemsListView(liveItems: displayLiveItems)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
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

            // AntennaPod-like Feed detail info bar (visible sort→chip→search list remaining time).
            // Distinct from Download all / Mark all as played / Add all to queue full-feed eligibility counts.
            if let remainingLabel = feedRemainingInfoLabel {
                Section {
                    Text(remainingLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(feedRemainingAccessibilityLabel)
                }
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
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
                .accessibilityLabel(String(localized: "Sort episodes"))
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
                        .accessibilityLabel(String(localized: "Share podcast"))
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

                        if let url = liveFeed.fundingURL {
                            Button {
                                openURL(url)
                            } label: {
                                Label(liveFeed.supportActionTitle, systemImage: "heart.circle")
                            }
                            .accessibilityLabel(liveFeed.supportAccessibilityLabel)
                            .accessibilityHint(String(localized: "Opens the funding page in the system browser"))
                        }

                        if let interact = liveFeed.preferredSocialInteract,
                           let url = interact.discussionURL {
                            Button {
                                openURL(url)
                            } label: {
                                Label("Discuss", systemImage: "bubble.left.and.bubble.right")
                            }
                            .accessibilityLabel(String(localized: "Discuss"))
                            .accessibilityHint(String(localized: "Opens the discussion link from the feed in the system browser"))
                        }

                        Button {
                            copyFeedURL()
                        } label: {
                            Label("Copy feed URL", systemImage: "doc.on.doc")
                        }
                        .disabled(!canCopyFeedURL)
                        .accessibilityLabel(String(localized: "Copy feed URL"))

                        if displayPodcastGuid != nil {
                            Button {
                                copyPodcastGuid()
                            } label: {
                                Label("Copy podcast GUID", systemImage: "number")
                            }
                            .accessibilityLabel(String(localized: "Copy podcast GUID"))
                            .accessibilityHint(String(localized: "Copies the podcast GUID from the feed to the pasteboard"))
                        }

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

                        Button {
                            showEnqueueAllConfirm = true
                        } label: {
                            Label("Add all to queue", systemImage: "text.append")
                        }
                        .disabled(enqueueAllFromFeedCandidatesCount == 0)
                        .accessibilityHint(String(localized: "Appends feed episodes not already queued"))

                        Button(role: .destructive) {
                            showUnsubscribeConfirm = true
                        } label: {
                            Label("Unsubscribe", systemImage: "trash")
                        }
                        .accessibilityHint(String(localized: "Opens unsubscribe confirmation; optional delete this feed’s downloads"))
                    } label: {
                        Label("Feed actions", systemImage: "ellipsis.circle")
                    }
                    Button {
                        showPerFeedSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(String(localized: "Podcast settings"))
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
            "Add all to queue?",
            isPresented: $showEnqueueAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Add all to queue") {
                store.enqueueAllFromFeed(liveFeed)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Appends \(enqueueAllFromFeedCandidatesCount) episodes from this podcast to the end of the queue (newest publish date first). Already queued episodes are skipped. Uses the full feed episode catalog (same honesty as Download all / Mark all as played), not the chip or search filter. Includes played and archived. Queue lock does not block enqueue."
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
            if unsubscribeFeedDownloadsCount > 0 {
                Button(
                    "Unsubscribe and delete \(unsubscribeFeedDownloadsCount) downloads (\(unsubscribeFeedDownloadsSizeLabel))",
                    role: .destructive
                ) {
                    downloads.deleteDownloads(forFeed: liveFeed)
                    store.unsubscribe(liveFeed)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if unsubscribeFeedDownloadsCount > 0 {
                Text(
                    "Unsubscribe from \"\(liveFeed.title)\"? Removes this podcast from Subscriptions, its feed settings and tags, queue items from this feed, and favorites, archive, and playback history for its episodes. This feed has \(unsubscribeFeedDownloadsCount) offline download(s) (\(unsubscribeFeedDownloadsSizeLabel)). Unsubscribe keeps those files; Unsubscribe and delete downloads removes only this feed’s offline files (incl. favorited). Does not clear other podcasts’ downloads or Clear all downloads."
                )
            } else {
                Text(
                    "Unsubscribe from \"\(liveFeed.title)\"? Removes this podcast from Subscriptions, its feed settings and tags, queue items from this feed, and favorites, archive, and playback history for its episodes. Downloaded files are kept."
                )
            }
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showFeedURLCopied
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "Feed URL copied to the pasteboard."))
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showPodcastGuidCopied
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "Podcast GUID copied to the pasteboard."))
        }
        .sensoryFeedback(.success, trigger: copyFeedURLFeedbackTick)
        .sensoryFeedback(.success, trigger: copyPodcastGuidFeedbackTick)
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

    /// Feed-provided Podcast Index `podcast:guid` only — never invent / never derive from feed URL.
    private func copyPodcastGuid() {
        guard let guid = displayPodcastGuid else { return }
        UIPasteboard.general.string = guid
        copyPodcastGuidFeedbackTick += 1
        showPodcastGuidCopied = true
    }

    /// Channel podcast:trailer row — title (+ optional season); Play via PlaybackService when enclosure-like, else openURL.
    @ViewBuilder
    private func feedTrailerRow(_ trailer: PodcastTrailer) -> some View {
        let title = trailer.displayTitle ?? trailer.title
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Trailer"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let season = trailer.season {
                Text(String(localized: "Season \(season)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if trailer.prefersInAppPlayback {
                Button {
                    playOrOpenTrailer(trailer)
                } label: {
                    Label("Play trailer", systemImage: "play.fill")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Play trailer"))
                .accessibilityHint(String(localized: "Plays the podcast trailer from the feed"))
            } else if trailer.mediaURL != nil {
                Button {
                    playOrOpenTrailer(trailer)
                } label: {
                    Label("Open trailer", systemImage: "safari")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Open trailer"))
                .accessibilityHint(String(localized: "Opens the trailer URL in the system browser"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    /// Prefer in-app play for enclosure-like http(s) media; fall back to system browser for other http(s).
    /// Uses `fromBeginning: true` so feed skip-intro does not clip the trailer.
    private func playOrOpenTrailer(_ trailer: PodcastTrailer) {
        if trailer.prefersInAppPlayback,
           let episode = trailer.asPlaybackEpisode(feedId: liveFeed.id) {
            if playback.play(episode: episode, fromBeginning: true) {
                return
            }
        }
        if let url = trailer.mediaURL {
            openURL(url)
        }
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

/// Wrapping itunes:category chips (Feed detail / description). Feed text only — no taxonomy mapping.
private struct FeedCategoryChips: View {
    let categories: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(categories, id: \.self) { name in
                Text(name)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .accessibilityLabel(String(localized: "Category \(name)"))
            }
        }
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
                    // itunes:explicit yes/true/explicit (item or inherited channel) — hide otherwise.
                    if episode.isExplicit {
                        Text(String(localized: "Explicit"))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2), in: Capsule())
                            .accessibilityHidden(true)
                    }
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
                if seasonEpisodeCaptionText != nil
                    || episodeTypeCaptionText != nil
                    || dateOverride != nil
                    || episode.pubDateEpochMs != nil
                    || formattedKnownDuration != nil
                    || formattedKnownByteSize != nil {
                    HStack(spacing: 6) {
                        if let seasonEpisodeCaptionText {
                            Text(seasonEpisodeCaptionText)
                                .monospacedDigit()
                        }
                        if let episodeTypeCaptionText {
                            if seasonEpisodeCaptionText != nil {
                                Text("·")
                                    .accessibilityHidden(true)
                            }
                            Text(episodeTypeCaptionText)
                        }
                        if let dateOverride {
                            // History / Favorites / Archived: live relative (hours matter).
                            if seasonEpisodeCaptionText != nil || episodeTypeCaptionText != nil {
                                Text("·")
                                    .accessibilityHidden(true)
                            }
                            Text(dateOverride, style: .relative)
                        } else if let caption = formattedPubDateCaption {
                            // Publish date: Today / Yesterday / N days ago / absolute.
                            if seasonEpisodeCaptionText != nil || episodeTypeCaptionText != nil {
                                Text("·")
                                    .accessibilityHidden(true)
                            }
                            Text(caption)
                        }
                        if let formattedKnownDuration {
                            if seasonEpisodeCaptionText != nil
                                || episodeTypeCaptionText != nil
                                || dateOverride != nil
                                || episode.pubDateEpochMs != nil {
                                Text("·")
                                    .accessibilityHidden(true)
                            }
                            Text(formattedKnownDuration)
                                .monospacedDigit()
                        }
                        if let formattedKnownByteSize {
                            if seasonEpisodeCaptionText != nil
                                || episodeTypeCaptionText != nil
                                || dateOverride != nil
                                || episode.pubDateEpochMs != nil
                                || formattedKnownDuration != nil {
                                Text("·")
                                    .accessibilityHidden(true)
                            }
                            Text(formattedKnownByteSize)
                                .monospacedDigit()
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                // AntennaPod-like: thin bar only for started-not-finished (position > 1, not isPlayed, duration known).
                if progressFraction > 0 {
                    ProgressView(value: progressFraction)
                        .tint(.accentColor)
                        .accessibilityHidden(true)
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

    /// Fraction of episode heard for the thin list ProgressView.
    /// Position + duration from `playback.json` (`EpisodePlaybackState`); duration may fall back
    /// to feed `itunes:duration` / media via `knownDurationSeconds` when playback duration is unset.
    /// Hidden (0) when unplayed (`position ≤ 1`), fully played (`isPlayed`), or duration unknown.
    private var progressFraction: Double {
        guard !state.isPlayed else { return 0 }
        let position = state.positionSeconds
        // Match Resume / Continue listening: ignore sub-second noise.
        guard position > 1, let duration = knownDurationSeconds, duration > 0 else {
            return 0
        }
        return min(1, position / duration)
    }

    /// Remaining wall-clock seconds when in-progress with known duration; else `nil`.
    private var remainingSeconds: Double? {
        guard progressFraction > 0, let duration = knownDurationSeconds else { return nil }
        let left = duration - state.positionSeconds
        guard left.isFinite, left > 0 else { return nil }
        return left
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

    /// VoiceOver summary: title, feed, Explicit when marked, season/episode, type, date, duration, size, played / percent (+ remaining) or position-only, downloaded (+ favorite/archived).
    private var episodeAccessibilityLabel: String {
        var parts: [String] = [episode.title]
        if !feedTitle.isEmpty {
            parts.append(feedTitle)
        }
        if episode.isExplicit {
            parts.append(String(localized: "Explicit"))
        }
        if let seasonA11y = episode.seasonEpisodeAccessibilityLabel {
            parts.append(seasonA11y)
        }
        if let typeCaption = episodeTypeCaptionText {
            parts.append(typeCaption)
        }
        if let dateOverride, let custom = dateAccessibilityLabel {
            parts.append(custom)
        } else if let caption = formattedPubDateCaption {
            parts.append(caption)
        }
        if let formattedKnownDuration {
            parts.append(String(localized: "Duration \(formattedKnownDuration)"))
        }
        if let formattedKnownByteSize {
            parts.append(String(localized: "Size \(formattedKnownByteSize)"))
        }
        if state.isPlayed {
            parts.append(String(localized: "Played"))
        } else if progressFraction > 0 {
            let pct = Int((progressFraction * 100).rounded())
            parts.append(String(localized: "\(pct) percent played"))
            if let remaining = remainingSeconds,
               let formatted = PodcastEpisode.formatPlaybackPosition(remaining) {
                parts.append(String(localized: "\(formatted) remaining"))
            }
        } else if !state.isPlayed, state.positionSeconds > 1 {
            // Duration unknown: no bar, but VoiceOver can still say saved position.
            if let formatted = PodcastEpisode.formatPlaybackPosition(state.positionSeconds) {
                parts.append(String(localized: "At \(formatted)"))
            }
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

    /// Compact iTunes season/episode (`S2 E5`) when feed provides numbers; nil when unknown.
    private var seasonEpisodeCaptionText: String? {
        episode.seasonEpisodeCaption
    }

    /// Trailer / Bonus when `itunes:episodeType` is trailer/bonus; nil for full/missing.
    private var episodeTypeCaptionText: String? {
        episode.episodeTypeCaption
    }

    /// Publish-date caption: Today / Yesterday / N days ago (≤7) / medium absolute.
    private var formattedPubDateCaption: String? {
        guard let ms = episode.pubDateEpochMs else { return nil }
        let date = Date(timeIntervalSince1970: Double(ms) / 1000)
        return EpisodeDateFormatting.listCaption(for: date)
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

    /// Prefer on-disk file size when an offline copy exists; else feed enclosure `PodcastEpisode.size` when > 0.
    /// Same honesty as Downloads rows (`DownloadedEpisode.knownByteSize`). Hidden when unknown — never invents MB.
    private var knownByteSize: Int64? {
        if let item = downloads.downloads.first(where: { $0.id == episode.id }) {
            return item.knownByteSize()
        }
        // Local-folder `file://` (or other localURL) not necessarily in the downloads catalog.
        if let url = downloads.localURL(for: episode) {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile != false,
               let size = values?.fileSize,
               size > 0 {
                return Int64(size)
            }
        }
        if episode.size > 0 {
            return episode.size
        }
        return nil
    }

    /// Compact KB/MB/GB via `DownloadStorageUsage.formatBytes` / `ByteCountFormatter` when `knownByteSize` is set.
    private var formattedKnownByteSize: String? {
        guard let bytes = knownByteSize else { return nil }
        return DownloadStorageUsage.formatBytes(bytes)
    }
}
