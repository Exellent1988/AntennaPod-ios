import AVFoundation
import SwiftUI
import UIKit

/// Full-screen / sheet player opened from the mini player (AntennaPod P0).
struct FullPlayerView: View {
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var downloads: DownloadService
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var isScrubbing = false
    @State private var scrubSeconds: Double = 0
    /// Chapters loaded from Podcast Index JSON when the feed only had a URL.
    @State private var remoteChapters: [PodcastChapter] = []
    /// In-flight Full Player chapter load. Cancelled when the episode changes so a
    /// late Podcast Index / media read cannot replace the new episode's chapter list.
    @State private var chapterLoadTask: Task<Void, Never>?
    /// Chapters read from a local media file (QuickTime/MP4) when feed has none.
    @State private var mediaChapters: [PodcastChapter] = []
    @State private var isLoadingRemoteChapters = false
    @State private var isLoadingMediaChapters = false
    @State private var showTranscript = false
    @State private var showDescription = false
    @State private var showFeedUnavailable = false
    @State private var showCustomSleepTimer = false
    @State private var showCustomPlaybackSpeed = false
    @State private var showJumpToPosition = false
    @State private var showBookmarks = false
    @State private var showEpisodePrivateNote = false
    @State private var showCopiedAlert = false
    @State private var copiedAlertMessage = ""
    @State private var copyURLFeedbackTick = 0
    /// Single download pending Full Player delete confirmation (nil = dialog dismissed).
    @State private var episodePendingDeleteDownload: PodcastEpisode?
    /// Single episode pending Full Player Remove-from-queue confirmation (nil = dialog dismissed).
    @State private var episodePendingRemoveFromQueue: PodcastEpisode?

    /// Chapter list `.searchable` (filters already-loaded titles only).
    @State private var chapterSearchText = ""
    @State private var chapterDebouncedQuery = ""
    @State private var chapterDebounceTask: Task<Void, Never>?

    private let chapterDebounceNs: UInt64 = 250_000_000 // 250 ms

    private var episode: PodcastEpisode? { playback.currentEpisode }

    private var feed: PodcastFeed? {
        guard let episode else { return nil }
        return store.feed(containingEpisodeId: episode.id)
    }

    /// Local nickname when set, else RSS title (player Open podcast label).
    private var feedDisplayTitle: String? {
        feed.map { store.displayTitle(for: $0) }
    }

    /// Prefer store episode (post-refresh) over a possibly stale player/queue copy.
    private var resolvedEpisode: PodcastEpisode? {
        guard let episode else { return nil }
        return store.episode(id: episode.id) ?? episode
    }

    /// Prefer item `podcast:images`/`podcast:image`, then channel variants / classic `imageUrl`. One URL only — no eager multi-download.
    private var preferredArtworkURLString: String? {
        if let ep = resolvedEpisode, let fromItem = ep.preferredPodcastImagesArtworkURL {
            return fromItem
        }
        return feed?.preferredDisplayArtworkURL
    }

    /// Feed (inline PSC or fetched Podcast Index) preferred; else media-file chapters.
    private var feedChapters: [PodcastChapter] {
        if !remoteChapters.isEmpty { return remoteChapters }
        return resolvedEpisode?.chapters ?? []
    }

    private var chapters: [PodcastChapter] {
        ChapterMerger.preferFeed(feedChapters, elseMedia: mediaChapters)
    }

    private var isLoadingChapters: Bool {
        isLoadingRemoteChapters || isLoadingMediaChapters
    }

    /// Visible chapter indices after light-debounced case-insensitive title filter.
    private var filteredChapterIndices: [Int] {
        let q = chapterDebouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return Array(chapters.indices) }
        return chapters.indices.filter { chapters[$0].title.localizedSearchContains(q) }
    }

    private var isFilteringChapters: Bool {
        !chapterDebouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var displayPosition: Double {
        isScrubbing ? scrubSeconds : playback.positionSeconds
    }

    /// Jump-to-position needs a known finite duration and a current episode.
    private var canJumpToPosition: Bool {
        episode != nil
            && playback.durationSeconds.isFinite
            && playback.durationSeconds > 0
    }

    private var currentChapterIndex: Int? {
        ChapterIndexing.currentIndex(in: chapters, at: displayPosition)
    }

    /// Title of the active chapter at display position, or `nil` when none / empty.
    private var currentChapterTitle: String? {
        guard let index = currentChapterIndex else { return nil }
        let title = chapters[index].title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    /// Current chapter http(s) `img` when present — drives Full player large cover swap.
    /// Nil when no chapters / no image / non-http(s). Never invent; episode art is the fallback.
    private var currentChapterDisplayImageURL: URL? {
        guard let index = currentChapterIndex else { return nil }
        return chapters[index].displayImageURL
    }


    private var canSkipChapters: Bool { !chapters.isEmpty }

    private var previousChapterTarget: Double? {
        ChapterIndexing.previousSeekSeconds(in: chapters, at: displayPosition)
    }

    private var nextChapterTarget: Double? {
        ChapterIndexing.nextSeekSeconds(in: chapters, at: displayPosition)
    }

    /// Known episode duration for last-chapter end (live player → feed → saved playback).
    /// `nil` when unknown — last chapter duration/remaining stays hidden (no invented end).
    private var chapterEpisodeDurationSeconds: Double? {
        let live = playback.durationSeconds
        if live.isFinite, live > 0 { return live }
        if let episode = resolvedEpisode, episode.hasKnownDuration {
            return episode.durationSeconds
        }
        if let episode = resolvedEpisode ?? episode {
            let saved = store.playbackState(for: episode.id).durationSeconds
            if saved.isFinite, saved > 0 { return saved }
        }
        return nil
    }

    /// Total duration caption, never the live scrubber's remaining-time label.
    private var formattedKnownDuration: String? {
        guard let episode = resolvedEpisode ?? episode else { return nil }
        return EpisodeCopyLinks.formattedDuration(
            for: episode,
            liveDurationSeconds: playback.durationSeconds,
            savedDurationSeconds: store.playbackState(for: episode.id).durationSeconds
        )
    }

    /// Prefer the local copy's on-disk size, then the feed enclosure size.
    private var formattedKnownByteSize: String? {
        guard let episode = resolvedEpisode ?? episode else { return nil }
        return EpisodeCopyLinks.formattedByteSize(for: episode, downloads: downloads)
    }

    /// Same publish-date caption shown in EpisodeRow; hidden when feed metadata is missing.
    private var formattedPublishDate: String? {
        guard let episode = resolvedEpisode ?? episode else { return nil }
        return EpisodeCopyLinks.formattedPublishDate(for: episode)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let episode {
                    if chapters.isEmpty {
                        playerContent(episode: episode)
                    } else {
                        playerContent(episode: episode)
                            .searchable(text: $chapterSearchText, prompt: "Search chapters")
                            .onChange(of: chapterSearchText) { _, newValue in
                                scheduleChapterFilter(for: newValue)
                            }
                    }
                } else {
                    ContentUnavailableView(
                        String(localized: "Nothing playing"),
                        systemImage: "play.slash",
                        description: Text(String(localized: "Start an episode from Inbox, Queue, or a feed."))
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized: "Nothing playing"))
                    .accessibilityValue(String(localized: "No episode is currently loaded"))
                    .accessibilityHint(
                        String(localized: "Start an episode from Inbox, Queue, or a feed to use the player controls.")
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .accessibilityLabel(String(localized: "Close player"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        openPodcastFromPlayer()
                    } label: {
                        Image(systemName: "dot.radiowaves.left.and.right")
                    }
                    .disabled(feed == nil)
                    .accessibilityLabel(String(localized: "Open podcast"))
                    .accessibilityHint(
                        feed == nil
                            ? String(localized: "Podcast unavailable")
                            : String(localized: "Opens this episode's podcast in Subscriptions")
                    )
                }
                if let episode, showsVideoSurface(for: episode) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            playback.pictureInPicture.toggle()
                        } label: {
                            Image(systemName: playback.pictureInPicture.isActive ? "pip.exit" : "pip.enter")
                        }
                        .disabled(!playback.pictureInPicture.isPossible && !playback.pictureInPicture.isActive)
                        .accessibilityLabel(String(localized: "Picture in Picture"))
                        .accessibilityValue(
                            playback.pictureInPicture.isActive
                                ? String(localized: "On")
                                : String(localized: "Off")
                        )
                        .accessibilityHint(
                            playback.pictureInPicture.isActive
                                ? String(localized: "Stops Picture in Picture")
                                : playback.pictureInPicture.isPossible
                                    ? String(localized: "Starts Picture in Picture")
                                    : String(localized: "Unavailable until Picture in Picture is ready")
                        )
                        .accessibilityAddTraits(playback.pictureInPicture.isActive ? .isSelected : [])
                    }
                }
            }
        }
        .onAppear {
            scrubSeconds = playback.positionSeconds
            scheduleChapterLoad()
        }
        .onDisappear {
            chapterDebounceTask?.cancel()
            chapterLoadTask?.cancel()
        }
        .onChange(of: playback.currentEpisode?.id) { _, newId in
            playback.pictureInPicture.tearDown()
            chapterLoadTask?.cancel()
            remoteChapters = []
            mediaChapters = []
            isLoadingRemoteChapters = false
            isLoadingMediaChapters = false
            if newId == nil {
                dismiss()
                return
            }
            scrubSeconds = playback.positionSeconds
            isScrubbing = false
            showTranscript = false
            showDescription = false
            // Bookmarks sheet reads the live episode. Leaving it open after auto-next
            // retargets the list, note, and delete onto the next episode.
            showBookmarks = false
            // Private note sheet writes to the episode id it was given. Leaving it
            // open after auto-next saves the draft or a clear onto the next episode.
            showEpisodePrivateNote = false
            // Jump sheet keeps the typed time in local state and seeks the live item.
            // Leaving it open after auto-next seeks that time on the next episode.
            showJumpToPosition = false
            // Speed sheet keeps the typed speed and Set applies it to whatever is now playing.
            showCustomPlaybackSpeed = false
            resetChapterSearch()
            scheduleChapterLoad()
        }
        .onChange(of: settings.playVideoAsAudioOnly) { _, audioOnly in
            if audioOnly {
                playback.pictureInPicture.tearDown()
            }
        }
        // Nested ObservableObject — forward publishes so PiP button enablement refreshes.
        .onReceive(playback.pictureInPicture.objectWillChange) { _ in
            // Touch published flags so body re-reads isPossible / isActive.
            _ = playback.pictureInPicture.isPossible
            _ = playback.pictureInPicture.isActive
        }
        .sheet(isPresented: $showTranscript) {
            if let episode = resolvedEpisode ?? episode {
                TranscriptSheetView(episode: episode)
                    .environmentObject(playback)
            }
        }
        .sheet(isPresented: $showDescription) {
            if let episode = resolvedEpisode ?? episode {
                EpisodeDescriptionSheetView(episode: episode, feedTitle: feedDisplayTitle)
            }
        }
        .alert(
            String(localized: "Podcast unavailable"),
            isPresented: $showFeedUnavailable
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(localized: "This episode is not linked to a subscribed podcast."))
        }
        .alert(
            String(localized: "Copied"),
            isPresented: $showCopiedAlert
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(copiedAlertMessage)
        }
        .confirmationDialog(
            "Delete download?",
            isPresented: Binding(
                get: { episodePendingDeleteDownload != nil },
                set: { if !$0 { episodePendingDeleteDownload = nil } }
            ),
            titleVisibility: .visible,
            presenting: episodePendingDeleteDownload
        ) { episode in
            Button("Delete download", role: .destructive) {
                downloads.delete(episode)
                episodePendingDeleteDownload = nil
            }
            Button("Cancel", role: .cancel) {
                episodePendingDeleteDownload = nil
            }
        } message: { episode in
            Text(
                "Delete download for \"\(episode.title)\"? Removes the local offline file only. Keeps played status, queue, and favorites."
            )
        }
        .confirmationDialog(
            "Remove from queue?",
            isPresented: Binding(
                get: { episodePendingRemoveFromQueue != nil },
                set: { if !$0 { episodePendingRemoveFromQueue = nil } }
            ),
            titleVisibility: .visible,
            presenting: episodePendingRemoveFromQueue
        ) { episode in
            Button("Remove from queue", role: .destructive) {
                store.removeFromQueue(episode)
                episodePendingRemoveFromQueue = nil
            }
            Button("Cancel", role: .cancel) {
                episodePendingRemoveFromQueue = nil
            }
        } message: { episode in
            Text(
                "Remove \"\(episode.title)\" from the queue? Removes from the queue only. Does not delete the download, mark played, or stop playback."
            )
        }
        .sensoryFeedback(.success, trigger: copyURLFeedbackTick)
        .sheet(isPresented: $showCustomSleepTimer) {
            CustomSleepTimerSheet(initialMinutes: settings.lastCustomSleepTimerMinutes)
                .environmentObject(playback)
                .environmentObject(settings)
        }
        .sheet(isPresented: $showCustomPlaybackSpeed) {
            CustomPlaybackSpeedSheet(mode: .session, initialSpeed: playback.rate)
                .environmentObject(playback)
                .environmentObject(settings)
        }
        .sheet(isPresented: $showJumpToPosition) {
            JumpToPositionSheet(initialSeconds: displayPosition)
                .environmentObject(playback)
                .onDisappear {
                    scrubSeconds = playback.positionSeconds
                    isScrubbing = false
                }
        }
        .sheet(isPresented: $showBookmarks) {
            if let episode {
                EpisodeBookmarksSheet(episodeId: episode.id)
                    .environmentObject(playback)
                    .environmentObject(store)
                    .onDisappear {
                        scrubSeconds = playback.positionSeconds
                        isScrubbing = false
                    }
            }
        }
        .sheet(isPresented: $showEpisodePrivateNote) {
            if let episode {
                EpisodePrivateNoteSheet(episodeId: episode.id)
                    .environmentObject(store)
            }
        }
    }

    @ViewBuilder
    private func playerContent(episode: PodcastEpisode) -> some View {
        GeometryReader { geo in
            let side = min(geo.size.width - 48, 320)
            ScrollView {
                VStack(spacing: 24) {
                    mediaSurface(episode: episode, side: side)
                        .padding(.top, 8)
                    videoAudioOnlyToggle(episode: episode)
                        .padding(.horizontal)
                    VStack(spacing: 6) {
                        Text(episode.title)
                            .font(.title2.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                        if let podcastTitle = EpisodeCopyLinks.trimmedFeedTitle(feedDisplayTitle) {
                            Button {
                                openPodcastFromPlayer()
                            } label: {
                                Text(podcastTitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(localized: "Open podcast"))
                            .accessibilityValue(podcastTitle)
                            .accessibilityHint(String(localized: "Opens this episode's podcast in Subscriptions"))

                            episodeMetadataActions(
                                text: podcastTitle,
                                copyLabel: String(localized: "Copy podcast title"),
                                shareLabel: String(localized: "Share podcast title"),
                                copyHint: String(localized: "Copies the trimmed podcast display title to the pasteboard; hidden when the title is empty; no title invented"),
                                shareHint: String(localized: "Shares the trimmed podcast display title as plain text; hidden when the title is empty; no title invented"),
                                copiedMessage: String(localized: "Podcast title copied to the pasteboard.")
                            )
                        }
                        // Item season/episode and itunes:episodeType metadata; hide when missing, never invent.
                        if let seasonEpisodeCaption = episode.seasonEpisodeCaption {
                            Text(seasonEpisodeCaption)
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                                .accessibilityLabel(episode.seasonEpisodeAccessibilityLabel ?? seasonEpisodeCaption)
                            episodeMetadataActions(
                                text: seasonEpisodeCaption,
                                copyLabel: String(localized: "Copy season and episode"),
                                shareLabel: String(localized: "Share season and episode"),
                                copyHint: String(localized: "Copies the same season and episode caption shown above to the pasteboard; item metadata only; no numbers invented"),
                                shareHint: String(localized: "Shares the same season and episode caption shown above as plain text; item metadata only; no numbers invented"),
                                copiedMessage: String(localized: "Season and episode copied to the pasteboard.")
                            )
                        }
                        if episode.isExplicit {
                            Text(String(localized: "Explicit"))
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                                .accessibilityLabel(String(localized: "Explicit"))
                            episodeMetadataActions(
                                text: String(localized: "Explicit"),
                                copyLabel: String(localized: "Copy episode explicit badge"),
                                shareLabel: String(localized: "Share episode explicit badge"),
                                copyHint: String(localized: "Copies the localized Explicit badge shown above for this episode to the pasteboard; display-only; does not enforce content restrictions"),
                                shareHint: String(localized: "Shares the localized Explicit badge shown above for this episode as plain text; display-only; does not enforce content restrictions"),
                                copiedMessage: String(localized: "Episode explicit badge copied to the pasteboard.")
                            )
                        }
                        if let medium = episode.displayMedium {
                            Text(medium)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                                .accessibilityLabel(String(localized: "Medium \(medium)"))
                            episodeMetadataActions(
                                text: medium,
                                copyLabel: String(localized: "Copy episode medium"),
                                shareLabel: String(localized: "Share episode medium"),
                                copyHint: String(localized: "Copies the same item-provided medium string shown above to the pasteboard; display-only; no playback change or remapping"),
                                shareHint: String(localized: "Shares the same item-provided medium string shown above as plain text; display-only; no playback change or remapping"),
                                copiedMessage: String(localized: "Episode medium copied to the pasteboard.")
                            )
                        }
                        if let episodeType = episode.displayEpisodeType {
                            Text(episodeType)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                                .accessibilityLabel(episode.episodeTypeAccessibilityLabel ?? episodeType)
                            episodeMetadataActions(
                                text: episodeType,
                                copyLabel: String(localized: "Copy episode type"),
                                shareLabel: String(localized: "Share episode type"),
                                copyHint: String(localized: "Copies the same item itunes:episodeType label shown above to the pasteboard; distinct from channel podcast:trailer"),
                                shareHint: String(localized: "Shares the same item itunes:episodeType label shown above as plain text; distinct from channel podcast:trailer"),
                                copiedMessage: String(localized: "Episode type copied to the pasteboard.")
                            )
                        }
                        if let formattedPublishDate {
                            Text(formattedPublishDate)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                                .accessibilityLabel(String(localized: "Publish date \(formattedPublishDate)"))
                            episodeMetadataActions(
                                text: formattedPublishDate,
                                copyLabel: String(localized: "Copy episode publish date"),
                                shareLabel: String(localized: "Share episode publish date"),
                                copyHint: String(localized: "Copies the same publish-date caption shown above to the pasteboard; known feed metadata only; no date invented"),
                                shareHint: String(localized: "Shares the same publish-date caption shown above as plain text; known feed metadata only; no date invented"),
                                copiedMessage: String(localized: "Episode publish date copied to the pasteboard.")
                            )
                        }
                        if let formattedKnownDuration {
                            Text(formattedKnownDuration)
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                                .accessibilityLabel(String(localized: "Duration \(formattedKnownDuration)"))
                            episodeMetadataActions(
                                text: formattedKnownDuration,
                                copyLabel: String(localized: "Copy episode duration"),
                                shareLabel: String(localized: "Share episode duration"),
                                copyHint: String(localized: "Copies the same duration caption shown above to the pasteboard; feed or known playback metadata only; no length invented"),
                                shareHint: String(localized: "Shares the same duration caption shown above as plain text; feed or known playback metadata only; no length invented"),
                                copiedMessage: String(localized: "Episode duration copied to the pasteboard.")
                            )
                        }
                        if let formattedKnownByteSize {
                            Text(formattedKnownByteSize)
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                                .accessibilityLabel(String(localized: "Size \(formattedKnownByteSize)"))
                            episodeMetadataActions(
                                text: formattedKnownByteSize,
                                copyLabel: String(localized: "Copy episode file size"),
                                shareLabel: String(localized: "Share episode file size"),
                                copyHint: String(localized: "Copies the same file-size caption shown above to the pasteboard; on-disk or feed enclosure metadata only; no size invented"),
                                shareHint: String(localized: "Shares the same file-size caption shown above as plain text; on-disk or feed enclosure metadata only; no size invented"),
                                copiedMessage: String(localized: "Episode file size copied to the pasteboard.")
                            )
                        }
                        if let title = EpisodeCopyLinks.trimmedTitle(for: episode) {
                            episodeMetadataActions(
                                text: title,
                                copyLabel: String(localized: "Copy episode title"),
                                shareLabel: String(localized: "Share episode title"),
                                copyHint: String(localized: "Copies the trimmed episode title to the pasteboard; hidden when the title is empty; no title invented"),
                                shareHint: String(localized: "Shares the trimmed episode title as plain text; hidden when the title is empty; no title invented"),
                                copiedMessage: String(localized: "Episode title copied to the pasteboard.")
                            )
                        }
                        if let titleAndPodcast = EpisodeCopyLinks.trimmedTitleAndPodcast(
                            episode: episode,
                            feedTitle: feedDisplayTitle
                        ) {
                            episodeMetadataActions(
                                text: titleAndPodcast,
                                copyLabel: String(localized: "Copy title and podcast"),
                                shareLabel: String(localized: "Share title and podcast"),
                                copyHint: String(localized: "Copies the trimmed episode title and podcast display title as `title — podcast`; hidden unless both are present; no title invented"),
                                shareHint: String(localized: "Shares the trimmed episode title and podcast display title as `title — podcast` plain text; hidden unless both are present; no title invented"),
                                copiedMessage: String(localized: "Title and podcast copied to the pasteboard.")
                            )
                        }
                        if let chapterTitle = currentChapterTitle {
                            Text(chapterTitle)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .accessibilityLabel(String(localized: "Chapter \(chapterTitle)"))
                        }
                        Label(
                            playback.isPlayingFromLocalFile ? String(localized: "Playing from download") : String(localized: "Streaming"),
                            systemImage: playback.isPlayingFromLocalFile ? "internaldrive" : "wifi"
                        )
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel(playback.isPlayingFromLocalFile ? String(localized: "Playing from download") : String(localized: "Streaming"))
                        if store.hasEpisodePrivateNote(for: episode.id) {
                            Button {
                                showEpisodePrivateNote = true
                            } label: {
                                Label(String(localized: "Private note"), systemImage: "note.text")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(localized: "Private note"))
                            .accessibilityValue(store.episodePrivateNote(for: episode.id) ?? "")
                            .accessibilityHint(String(localized: "Opens the private note editor for this episode"))
                        }
                    }
                    .padding(.horizontal)

                    scrubber
                        .padding(.horizontal)

                    chapterSkipControls
                        .padding(.horizontal)

                    transportControls
                        .padding(.horizontal)

                    // Prefer store episode for link/enclosure fields (post-refresh).
                    secondaryActions(episode: resolvedEpisode ?? episode)
                        .padding(.horizontal)

                    chaptersSection
                        .padding(.horizontal)

                    soundbitesSection
                        .padding(.horizontal)

                    alternateEnclosuresSection
                        .padding(.horizontal)

                    descriptionButton
                        .padding(.horizontal)

                    transcriptButton
                        .padding(.horizontal)

                    Spacer(minLength: 24)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    @ViewBuilder
    @ViewBuilder
    private var chaptersSection: some View {
        let chaptersEpisode = resolvedEpisode ?? episode
        let showChaptersURL = chaptersEpisode?.hasPodcastIndexChapterURL == true
        if isLoadingChapters && chapters.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ProgressView()
                    Text("Loading chapters…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let ep = chaptersEpisode, showChaptersURL {
                    PodcastChaptersURLView(episode: ep, showsSectionTitle: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        } else if !chapters.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text("Chapters")
                        .font(.headline)
                    Spacer(minLength: 8)
                    Button {
                        copyChaptersTOC()
                    } label: {
                        Image(systemName: "doc.plaintext")
                    }
                    .disabled(!canExportChaptersTOC)
                    .accessibilityLabel(String(localized: "Copy chapters"))
                    .accessibilityHint(String(localized: "Copies the chapter table of contents to the pasteboard"))

                    Button {
                        copyCurrentChapter()
                    } label: {
                        Image(systemName: "text.quote")
                    }
                    .disabled(!canCopyCurrentChapter)
                    .accessibilityLabel(String(localized: "Copy current chapter"))
                    .accessibilityHint(
                        String(localized: "Copies the current chapter to the pasteboard")
                    )

                    ShareLink(
                        item: currentChapterShareText,
                        subject: Text(chaptersEpisode?.title ?? String(localized: "Chapters"))
                    ) {
                        Image(systemName: "quote.bubble")
                    }
                    .disabled(!canShareCurrentChapter)
                    .accessibilityLabel(String(localized: "Share current chapter"))
                    .accessibilityHint(
                        String(localized: "Opens the system share sheet with the episode title and current chapter")
                    )

                    ShareLink(
                        item: chaptersTOCShareText,
                        subject: Text(chaptersEpisode?.title ?? String(localized: "Chapters"))
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(!canExportChaptersTOC)
                    .accessibilityLabel(String(localized: "Share chapters"))
                    .accessibilityHint(
                        String(localized: "Opens the system share sheet with the episode title and chapter table of contents")
                    )
                }
                if isFilteringChapters && filteredChapterIndices.isEmpty {
                    ContentUnavailableView(
                        "No matching chapters",
                        systemImage: "magnifyingglass",
                        description: Text("No chapters match your search.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .accessibilityElement(children: .combine)
                } else {
                    ForEach(filteredChapterIndices, id: \.self) { index in
                        let chapter = chapters[index]
                        ChapterListRow(
                            startTimeText: format(chapter.startTimeSeconds),
                            title: chapter.title,
                            imageURL: chapter.displayImageURL,
                            linkURL: chapter.displayLinkURL,
                            trailingTimeLabel: chapterTrailingTimeLabel(index: index),
                            isCurrent: index == currentChapterIndex,
                            accessibilityBaseLabel: chapterAccessibilityLabel(index: index, chapter: chapter),
                            onSeek: {
                                seekToChapter(chapter.startTimeSeconds)
                            }
                        )
                    }
                }
                if let ep = chaptersEpisode, showChaptersURL {
                    PodcastChaptersURLView(episode: ep, showsSectionTitle: true)
                        .padding(.top, 4)
                }
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let ep = chaptersEpisode, showChaptersURL {
            // URL present but no loaded chapters (fetch failed / empty) — still offer Open / Copy.
            PodcastChaptersURLView(episode: ep, showsSectionTitle: true)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // No chapters and no remote URL → hide section entirely (no empty placeholder).
    }

    /// Item podcast:soundbite — feed-provided only; Play soundbite via PlaybackService (seek + auto-pause at end); no separate clip player.
    /// Prefer store-resolved episode so refresh-populated soundbites appear without restarting playback.
    @ViewBuilder
    private var soundbitesSection: some View {
        if let ep = resolvedEpisode ?? episode, !ep.displaySoundbites.isEmpty {
            PodcastSoundbitesListView(
                soundbites: ep.displaySoundbites,
                episode: ep
            )
            .padding(.top, 8)
        }
    }

    /// Item podcast:alternateEnclosure — http(s) Play same episode via preferredMediaURL; ipfs/magnet Copy.
    /// Prefer store-resolved episode so refresh-populated alternates appear without restarting playback.
    @ViewBuilder
    private var alternateEnclosuresSection: some View {
        if let ep = resolvedEpisode ?? episode, !ep.displayAlternateEnclosures.isEmpty {
            PodcastAlternateEnclosuresListView(
                alternateEnclosures: ep.displayAlternateEnclosures,
                episode: ep
            )
            .padding(.top, 8)
        }
    }

    /// Plain TOC from the **full** already-known chapter array — ignores search filter.
    private var chaptersTOCPlain: String {
        ChaptersTOCExport.plainText(from: chapters)
    }

    private var canExportChaptersTOC: Bool {
        !chaptersTOCPlain.isEmpty
    }

    /// Episode title + TOC body for system share sheet (same body as Copy).
    private var chaptersTOCShareText: String {
        ChaptersTOCExport.shareText(
            from: chapters,
            episodeTitle: (resolvedEpisode ?? episode)?.title
        )
    }

    /// One-line pasteboard text for the chapter active at playback position (full loaded array).
    /// Same TOC line format as Copy chapters; uses `ChapterIndexing.currentIndex`.
    private var currentChapterPlainForCopy: String? {
        ChaptersTOCExport.currentChapterPlainText(from: chapters, at: displayPosition)
    }

    /// Enabled when `ChapterIndexing` reports a current chapter (nil when empty / before first).
    private var canCopyCurrentChapter: Bool {
        currentChapterPlainForCopy != nil
    }

    /// Same gate as Copy current chapter — Share only when a current chapter exists.
    private var canShareCurrentChapter: Bool { canCopyCurrentChapter }

    /// Episode title + one-line current chapter for system share sheet (same body as Copy).
    private var currentChapterShareText: String {
        ChaptersTOCExport.currentChapterShareText(
            from: chapters,
            at: displayPosition,
            episodeTitle: (resolvedEpisode ?? episode)?.title
        )
    }

    private func copyChaptersTOC() {
        let text = chaptersTOCPlain
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        copiedAlertMessage = String(localized: "Chapters copied to the pasteboard.")
        copyURLFeedbackTick += 1
        showCopiedAlert = true
    }

    private func copyCurrentChapter() {
        guard let text = currentChapterPlainForCopy, !text.isEmpty else { return }
        UIPasteboard.general.string = text
        copiedAlertMessage = String(localized: "Current chapter copied to the pasteboard.")
        copyURLFeedbackTick += 1
        showCopiedAlert = true
    }

    private func resetChapterSearch() {

        chapterDebounceTask?.cancel()
        chapterSearchText = ""
        chapterDebouncedQuery = ""
    }

    private func scheduleChapterFilter(for term: String) {
        chapterDebounceTask?.cancel()
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            chapterDebouncedQuery = ""
            return
        }
        chapterDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: chapterDebounceNs)
            guard !Task.isCancelled else { return }
            chapterDebouncedQuery = trimmed
        }
    }

    /// Trailing time for a chapter row: current → live remaining (−m:ss) when end known;
    /// otherwise chapter duration when known. Hidden when times cannot be derived honestly.
    /// Current remaining follows Settings → Remaining time respects speed (same as mini/full
    /// −remaining); chapter **duration** stays wall-clock.
    private func chapterTrailingTimeLabel(index: Int) -> String? {
        let episodeDuration = chapterEpisodeDurationSeconds
        if index == currentChapterIndex,
           let wall = ChapterIndexing.remainingSeconds(
               in: chapters,
               atIndex: index,
               positionSeconds: displayPosition,
               episodeDurationSeconds: episodeDuration
           ) {
            return formatRemaining(displayChapterRemainingSeconds(wall))
        }
        if let duration = ChapterIndexing.durationSeconds(
            in: chapters,
            atIndex: index,
            episodeDurationSeconds: episodeDuration
        ) {
            return format(duration)
        }
        return nil
    }

    private func chapterAccessibilityLabel(index: Int, chapter: PodcastChapter) -> String {
        var parts = [String(localized: "Chapter \(chapter.title), \(format(chapter.startTimeSeconds))")]
        let episodeDuration = chapterEpisodeDurationSeconds
        if index == currentChapterIndex,
           let wall = ChapterIndexing.remainingSeconds(
               in: chapters,
               atIndex: index,
               positionSeconds: displayPosition,
               episodeDurationSeconds: episodeDuration
           ) {
            let display = displayChapterRemainingSeconds(wall)
            parts.append(String(localized: "\(format(display)) remaining"))
        } else if let duration = ChapterIndexing.durationSeconds(
            in: chapters,
            atIndex: index,
            episodeDurationSeconds: episodeDuration
        ) {
            parts.append(String(localized: "Duration \(format(duration))"))
        }
        return parts.joined(separator: ", ")
    }

    /// Current-chapter remaining for list chrome. Wall-clock unless Remaining time respects
    /// speed — then ÷ live session rate (fallback feed/default, 0.5…3.0). Same helper as
    /// mini/full −remaining. Not used for Lock Screen / Now Playing / Widget / Watch.
    private func displayChapterRemainingSeconds(_ wallClockSeconds: Double) -> Double {
        let fallback: Float
        if let episode = resolvedEpisode ?? playback.currentEpisode {
            fallback = store.resolvedPlaybackSpeedForRemaining(for: episode)
        } else {
            fallback = max(
                EpisodeRemainingTime.minimumPlaybackSpeedDivisor,
                settings.defaultPlaybackSpeed
            )
        }
        return EpisodeRemainingTime.playerChromeRemainingSeconds(
            wallClockSeconds: wallClockSeconds,
            respectsSpeed: settings.remainingTimeRespectsSpeed,
            sessionRate: playback.rate,
            fallbackSpeed: fallback
        )
    }

    @ViewBuilder
    private var descriptionButton: some View {
        let ep = resolvedEpisode ?? episode
        if let ep {
            Button {
                showDescription = true
            } label: {
                Label("Shownotes", systemImage: "doc.text")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
            .accessibilityLabel(String(localized: "Show shownotes"))
            .accessibilityHint(
                ep.hasDescriptionText
                    ? String(localized: "Opens the episode description from the feed")
                    : String(localized: "No description available for this episode")
            )
        }
    }

    @ViewBuilder
    private var transcriptButton: some View {
        let ep = resolvedEpisode ?? episode
        if let ep, ep.hasTranscriptURL {
            Button {
                showTranscript = true
            } label: {
                Label("Transcript", systemImage: "text.bubble")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
            .accessibilityLabel(String(localized: "Show transcript"))
            .accessibilityHint(String(localized: "Opens the feed-provided transcript"))
        }
    }

    /// Show video when the episode is video and audio-only mode is off.
    private func showsVideoSurface(for episode: PodcastEpisode) -> Bool {
        let ep = resolvedEpisode ?? episode
        return ep.isVideo && !settings.playVideoAsAudioOnly
    }

    @ViewBuilder
    private func mediaSurface(episode: PodcastEpisode, side: CGFloat) -> some View {
        if showsVideoSurface(for: episode), let player = playback.avPlayer {
            // One AVPlayer ↔ one AVPlayerLayer. While PiP holds the layer, show a placeholder.
            if playback.pictureInPicture.isActive {
                pipActivePlaceholder(side: side)
            } else {
                EpisodeVideoSurface(player: player, pictureInPicture: playback.pictureInPicture)
                    .frame(width: side, height: side * 9 / 16)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                    .accessibilityLabel(String(localized: "Video player"))
            }
        } else {
            artwork(side: side)
        }
    }

    @ViewBuilder
    private func videoAudioOnlyToggle(episode: PodcastEpisode) -> some View {
        let ep = resolvedEpisode ?? episode
        if ep.isVideo {
            Toggle(isOn: $settings.playVideoAsAudioOnly) {
                Label("Play video as audio only", systemImage: "speaker.wave.2")
            }
            .accessibilityHint(String(localized: "Hides the video surface, disables video tracks, and shows artwork. Lockscreen stays audio. Does not strip video from the file."))
        }
    }

    /// Large Full player cover: prefer current chapter http(s) image; on missing/fail → episode/feed art.
    /// Updates with `currentChapterIndex` (same source as chapter title highlight). List thumbs unchanged.
    /// Lock Screen / Now Playing / mini stay episode-level (see docs).
    @ViewBuilder
    private func artwork(side: CGFloat) -> some View {
        Group {
            if let chapterURL = currentChapterDisplayImageURL {
                AppAsyncImage(url: chapterURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        episodeArtworkContent
                    case .empty:
                        ZStack {
                            episodeArtworkContent
                            ProgressView()
                        }
                    @unknown default:
                        episodeArtworkContent
                    }
                }
                .id(chapterURL.absoluteString)
            } else {
                episodeArtworkContent
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        .accessibilityHidden(true)
    }

    /// Episode / feed artwork for Full player cover (fallback when chapter has no image or load fails).
    @ViewBuilder
    private var episodeArtworkContent: some View {
        if let urlString = preferredArtworkURLString, let url = EpisodeMediaURL.url(from: urlString) {
            AppAsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    artworkPlaceholder
                case .empty:
                    ZStack {
                        artworkPlaceholder
                        ProgressView()
                    }
                @unknown default:
                    artworkPlaceholder
                }
            }
        } else {
            artworkPlaceholder
        }
    }

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.quaternary)
            .overlay {
                Image(systemName: "waveform")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
            }
    }

    private func pipActivePlaceholder(side: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.black)
            .frame(width: side, height: side * 9 / 16)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "pip")
                        .font(.system(size: 36))
                    Text("Picture in Picture")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.9))
            }
            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
            .accessibilityLabel(String(localized: "Picture in Picture"))
            .accessibilityValue(String(localized: "Active"))
            .accessibilityHint(String(localized: "Video is currently shown in Picture in Picture."))
    }

    private var scrubber: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { displayPosition },
                    set: { scrubSeconds = $0 }
                ),
                in: 0...max(playback.durationSeconds.isFinite && playback.durationSeconds > 0
                    ? playback.durationSeconds
                    : max(displayPosition, 1), 1),
                onEditingChanged: { editing in
                    if editing {
                        isScrubbing = true
                        scrubSeconds = playback.positionSeconds
                    } else {
                        playback.seek(toSeconds: scrubSeconds)
                        isScrubbing = false
                    }
                }
            )
            .accessibilityLabel(String(localized: "Playback position"))
            .accessibilityValue(playbackPositionAccessibilityValue)
            .accessibilityHint(playbackPositionAccessibilityHint)
            // VoiceOver swipe up/down: the binding setter above only stores scrubSeconds and the
            // seek happens on drag end (onEditingChanged), which adjustments do not send, so a
            // swipe never moved playback (and the default step would be 10% of the episode).
            // Skip by the same intervals as the Forward / Rewind buttons instead.
            .accessibilityAdjustableAction { direction in
                isScrubbing = false
                switch direction {
                case .increment:
                    playback.seek(bySeconds: playback.fastForwardSeconds)
                case .decrement:
                    playback.seek(bySeconds: -playback.rewindSeconds)
                @unknown default:
                    break
                }
            }
            HStack {
                Button {
                    showJumpToPosition = true
                } label: {
                    HStack(spacing: 4) {
                        Text(format(displayPosition))
                            .font(.caption.monospacedDigit())
                        Image(systemName: "arrow.right.to.line")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canJumpToPosition)
                .accessibilityLabel(String(localized: "Jump to position"))
                .accessibilityValue(format(displayPosition))
                .accessibilityHint(
                    canJumpToPosition
                        ? String(localized: "Enter a time to seek")
                        : String(localized: "Duration unknown — jump unavailable.")
                )
                Spacer()
                Button {
                    settings.showRemainingTime.toggle()
                } label: {
                    Text(rightTimeLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    settings.showRemainingTime
                        ? String(localized: "Remaining time")
                        : String(localized: "Duration")
                )
                .accessibilityValue(rightTimeAccessibilityValue)
                .accessibilityHint(rightTimeAccessibilityHint)
            }
        }
    }

    /// Known finite duration from the player. Same gate as Jump to position.
    /// Does not invent an end time when false.
    private var hasKnownPlaybackDuration: Bool {
        playback.durationSeconds.isFinite && playback.durationSeconds > 0
    }

    /// VoiceOver for the scrubber. Visible clock stays position-only.
    /// Known duration names position of that duration. Unknown duration says so
    /// and does not invent an end. Not the right-hand remaining/duration label.
    private var playbackPositionAccessibilityValue: String {
        let position = format(displayPosition)
        if hasKnownPlaybackDuration {
            return String(
                format: String(localized: "Playback position %@ of %@"),
                position,
                format(playback.durationSeconds)
            )
        }
        return String(
            format: String(localized: "Playback position %@. Duration unknown."),
            position
        )
    }

    private var playbackPositionAccessibilityHint: String {
        if isScrubbing {
            if hasKnownPlaybackDuration {
                return String(localized: "Release seeks to this time within the known duration. No duration is invented.")
            }
            return String(localized: "Release seeks to this clock time. Duration is unknown, so this is not a fraction of the episode and no end time is invented.")
        }
        if hasKnownPlaybackDuration {
            return String(localized: "Drag to seek within the known episode duration. This is the live playback position, not a bookmark. It does not describe the right-hand time label.")
        }
        return String(localized: "Duration is unknown, so this is not a fraction of the episode and no end time is invented. Dragging seeks to a clock time. Jump to position stays unavailable until duration is known.")
    }

    /// Right scrubber label: total duration, or −remaining when Show remaining time is on.
    /// When Remaining time respects speed is on, −remaining ÷ live session rate
    /// (fallback feed/default, 0.5…3.0); otherwise wall-clock.
    private var rightTimeLabel: String {
        // Live streams and items still loading have no duration (0 / NaN). Showing
        // 0:00 or -0:00 invented an end; use the same placeholder as an unknown clock.
        guard hasKnownPlaybackDuration else { return "--:--" }
        if settings.showRemainingTime {
            let wall = playback.durationSeconds - displayPosition
            let fallback: Float
            if let episode = resolvedEpisode ?? playback.currentEpisode {
                fallback = store.resolvedPlaybackSpeedForRemaining(for: episode)
            } else {
                fallback = max(
                    EpisodeRemainingTime.minimumPlaybackSpeedDivisor,
                    settings.defaultPlaybackSpeed
                )
            }
            let display = EpisodeRemainingTime.playerChromeRemainingSeconds(
                wallClockSeconds: wall,
                respectsSpeed: settings.remainingTimeRespectsSpeed,
                sessionRate: playback.rate,
                fallbackSpeed: fallback
            )
            return formatRemaining(display)
        }
        return format(playback.durationSeconds)
    }

    /// VoiceOver for the right-hand time button. Visible clock stays as-is.
    /// Known duration names total duration, or remaining (wall-clock, or the
    /// live session rate when Remaining time respects speed is on). Unknown
    /// duration says so and does not invent an end. Not the scrubber.
    private var rightTimeAccessibilityValue: String {
        guard hasKnownPlaybackDuration else {
            return String(localized: "Duration unknown")
        }
        if settings.showRemainingTime {
            if settings.remainingTimeRespectsSpeed {
                return String(
                    format: String(localized: "Remaining %@, live playback speed"),
                    rightTimeLabel
                )
            }
            return String(
                format: String(localized: "Remaining %@, wall-clock"),
                rightTimeLabel
            )
        }
        return String(
            format: String(localized: "Total duration %@"),
            rightTimeLabel
        )
    }

    private var rightTimeAccessibilityHint: String {
        String(localized: "Right-hand time label. Not the playback-position scrubber and not Jump to position. Tap switches between total duration and remaining time. It does not seek, start playback, change the rate, or download. When duration is unknown, no time is invented. Remaining time is wall-clock unless Remaining time respects speed is on, then the live session rate from 0.5 to 3.0. Not Volume boost and not the list or Home remaining bars.")
    }

    @ViewBuilder
    private var chapterSkipControls: some View {
        if canSkipChapters {
            HStack(spacing: 40) {
                Button {
                    seekToChapter(previousChapterTarget)
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.title2)
                }
                .disabled(previousChapterTarget == nil)
                .accessibilityLabel(String(localized: "Previous chapter"))
                .accessibilityHint(String(localized: "Seeks to the previous chapter, or restarts the current chapter if more than 2 seconds in"))

                Button {
                    seekToChapter(nextChapterTarget)
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.title2)
                }
                .disabled(nextChapterTarget == nil)
                .accessibilityLabel(String(localized: "Next chapter"))
                .accessibilityHint(String(localized: "Seeks to the next chapter"))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
    }

    private func seekToChapter(_ seconds: Double?) {
        guard let seconds else { return }
        // A chapter start at or past a known duration used to seek to the last
        // second and leave the episode unplayed. Same finish path as Jump to position.
        let duration = playback.durationSeconds
        let finishes = duration.isFinite && duration > 0 && seconds >= duration
        playback.jumpToPosition(seconds: seconds)
        isScrubbing = false
        if !finishes {
            scrubSeconds = seconds
        }
    }

    /// One row at default sizes. At large accessibility text sizes the five controls are far
    /// wider than the screen, and the sleep countdown and speed text got squeezed to "…";
    /// fall back to a row of seek and play controls above a row with sleep timer and speed.
    private var transportControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 28) {
                sleepTimerMenu
                seekAndPlayButtons
                speedMenu
            }
            VStack(spacing: 16) {
                HStack(spacing: 28) {
                    seekAndPlayButtons
                }
                HStack(spacing: 28) {
                    sleepTimerMenu
                    speedMenu
                }
            }
            VStack(spacing: 16) {
                HStack(spacing: 28) {
                    seekAndPlayButtons
                }
                sleepTimerMenu
                speedMenu
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var seekAndPlayButtons: some View {
        Button {
            playback.seek(bySeconds: -playback.rewindSeconds)
        } label: {
            Image(systemName: AppSettings.skipSystemImage(forward: false, seconds: settings.rewindSeconds))
                .font(.title2)
        }
        .accessibilityLabel(String(localized: "Rewind \(settings.rewindSeconds) seconds"))

        Button {
            playback.togglePlayPause()
        } label: {
            Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 64))
        }
        .accessibilityLabel(playback.isPlaying ? String(localized: "Pause") : String(localized: "Play"))

        Button {
            playback.seek(bySeconds: playback.fastForwardSeconds)
        } label: {
            Image(systemName: AppSettings.skipSystemImage(forward: true, seconds: settings.fastForwardSeconds))
                .font(.title2)
        }
        .accessibilityLabel(String(localized: "Forward \(settings.fastForwardSeconds) seconds"))
    }

    private var speedMenu: some View {
        Menu {
            ForEach(AppSettings.speedPresets, id: \.self) { speed in
                Button {
                    playback.setRate(speed)
                } label: {
                    HStack {
                        Text(PlaybackService.formatPlaybackSpeed(speed))
                        if speed == settings.defaultPlaybackSpeed {
                            Text("Default")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Divider()
            Button(String(localized: "Custom…")) {
                showCustomPlaybackSpeed = true
            }
        } primaryAction: {
            playback.cycleToNextSpeedPreset()
        } label: {
            Text(PlaybackService.formatPlaybackSpeed(playback.rate))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(minWidth: 44)
        }
        .accessibilityLabel("\(String(localized: "Playback speed")) \(PlaybackService.formatPlaybackSpeed(playback.rate))")
        .accessibilityHint(String(localized: "Cycles to the next speed. Long-press for full list and Custom…"))
    }

    private var sleepTimerMenu: some View {
        Menu {
            if playback.isSleepTimerActive {
                if let label = playback.sleepTimerStatusLabel {
                    Text(String(format: String(localized: "Active · %@"), label))
                }
                Button("Extend +5 min") {
                    playback.extendSleepTimer(byMinutes: 5)
                }
                Button("Extend +10 min") {
                    playback.extendSleepTimer(byMinutes: 10)
                }
                Button("Turn off", role: .destructive) {
                    playback.disableSleepTimer()
                }
                Divider()
            }
            ForEach(PlaybackService.clockPresetsMinutes, id: \.self) { minutes in
                Button("\(minutes) min") {
                    playback.setSleepTimer(minutes: minutes)
                }
            }
            Button("End of episode") {
                playback.setSleepTimerEndOfEpisode()
            }
            Button(String(localized: "End of chapter")) {
                playback.setSleepTimerEndOfChapter()
            }
            .disabled(!canSleepTimerEndOfChapter)
            .accessibilityHint(
                canSleepTimerEndOfChapter
                    ? String(localized: "Pauses when the current chapter ends")
                    : String(localized: "No chapters available")
            )
            Button(String(localized: "End of queue")) {
                playback.setSleepTimerEndOfQueue()
            }
            .disabled(!canSleepTimerEndOfQueue)
            .accessibilityHint(
                canSleepTimerEndOfQueue
                    ? String(localized: "Stops after the last episode in the queue")
                    : String(localized: "Queue is empty")
            )
            Button(String(localized: "Custom…")) {
                showCustomSleepTimer = true
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "moon.zzz")
                    .font(.title3)
                if playback.isSleepTimerActive, let label = playback.sleepTimerStatusLabel {
                    Text(label)
                        .font(.caption.monospacedDigit())
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 44)
        }
        .accessibilityLabel(playback.sleepTimerAccessibilityLabel)
        .accessibilityHint(String(localized: "Sets or turns off the sleep timer"))
    }

    /// Prefer Full Player merged chapters (feed / remote / media) so the item enables after lazy load.
    private var canSleepTimerEndOfChapter: Bool {
        !chapters.isEmpty
    }

    /// Queue non-empty — EOQ uses `nextQueueEpisode` (head when current not queued).
    /// Disabled when empty even if something is playing (cannot drain a queue).
    private var canSleepTimerEndOfQueue: Bool {
        !store.queue.isEmpty
    }

    private func copyEpisodeLink(_ url: URL) {
        copiedAlertMessage = EpisodeCopyLinks.copyEpisodeLink(url)
        copyURLFeedbackTick += 1
        showCopiedAlert = true
    }

    private func copyMediaURL(_ rawURL: String) {
        copiedAlertMessage = EpisodeCopyLinks.copyMediaURL(rawURL)
        copyURLFeedbackTick += 1
        showCopiedAlert = true
    }

    @ViewBuilder
    private func episodeMetadataActions(
        text: String,
        copyLabel: String,
        shareLabel: String,
        copyHint: String,
        shareHint: String,
        copiedMessage: String
    ) -> some View {
        HStack(spacing: 12) {
            Button {
                copyEpisodeMetadata(text, message: copiedMessage)
            } label: {
                Label(copyLabel, systemImage: "doc.on.doc")
                    .font(.subheadline)
            }
            .accessibilityLabel(copyLabel)
            .accessibilityHint(copyHint)

            ShareLink(
                item: text,
                subject: Text(episode?.title ?? "")
            ) {
                Label(shareLabel, systemImage: "square.and.arrow.up")
                    .font(.subheadline)
            }
            .accessibilityLabel(shareLabel)
            .accessibilityHint(shareHint)
        }
    }

    private func copyEpisodeMetadata(_ text: String, message: String) {
        UIPasteboard.general.string = text
        copiedAlertMessage = message
        copyURLFeedbackTick += 1
        showCopiedAlert = true
    }

    private func secondaryActions(episode: PodcastEpisode) -> some View {
        let played = store.isPlayed(episode.id)
        let favorited = store.isFavorite(episode.id)
        let archived = store.isArchived(episode.id)
        return HStack(spacing: 16) {
            Button {
                playback.playFromBeginning()
            } label: {
                Label("Play from beginning", systemImage: "backward.end.fill")
            }
            .accessibilityLabel(String(localized: "Play from beginning"))
            .accessibilityHint(String(localized: "Seeks to the start of this episode and plays"))

            Button {
                showBookmarks = true
            } label: {
                Label("Bookmarks", systemImage: "bookmark")
            }
            .accessibilityLabel(String(localized: "Bookmarks"))
            .accessibilityHint(String(localized: "Lists bookmarks for this episode and saves the current position"))
            .accessibilityValue(bookmarksAccessibilityValue(for: episode.id))

            Button {
                showEpisodePrivateNote = true
            } label: {
                Label(
                    String(localized: "Private note…"),
                    systemImage: store.hasEpisodePrivateNote(for: episode.id) ? "note.text" : "square.and.pencil"
                )
            }
            .accessibilityLabel(String(localized: "Private note"))
            .accessibilityHint(String(localized: "Opens the private note editor for this episode"))
            .accessibilityValue(
                store.hasEpisodePrivateNote(for: episode.id)
                    ? String(localized: "Has private note")
                    : String(localized: "Empty")
            )

            Button {
                store.togglePlayed(episode.id)
            } label: {
                Label(
                    played ? String(localized: "Mark unplayed") : String(localized: "Mark played"),
                    systemImage: played ? "circle" : "checkmark.circle"
                )
            }
            .accessibilityLabel(
                played
                    ? String(localized: "Mark unplayed")
                    : String(localized: "Mark played")
            )
            .accessibilityHint(
                played
                    ? String(localized: "Marks this episode as unplayed")
                    : String(localized: "Marks this episode as played")
            )

            Button {
                store.toggleFavorite(episode.id)
            } label: {
                Label(
                    favorited ? String(localized: "Unfavorite") : String(localized: "Favorite"),
                    systemImage: favorited ? "star.fill" : "star"
                )
            }
            .tint(favorited ? .yellow : nil)
            .accessibilityLabel(
                favorited
                    ? String(localized: "Remove from favorites")
                    : String(localized: "Add to favorites")
            )
            .accessibilityHint(
                favorited
                    ? String(localized: "Removes this episode from favorites")
                    : String(localized: "Adds this episode to favorites")
            )

            Button {
                store.toggleArchived(episode.id)
            } label: {
                Label(
                    archived ? String(localized: "Restore") : String(localized: "Archive"),
                    systemImage: archived ? "archivebox.fill" : "archivebox"
                )
            }
            .tint(archived ? .orange : nil)
            .accessibilityLabel(
                archived
                    ? String(localized: "Restore")
                    : String(localized: "Archive")
            )
            .accessibilityHint(
                archived
                    ? String(localized: "Restores this episode from the archive")
                    : String(localized: "Hides this episode from Inbox without marking it played")
            )

            // Queue menu: crowded HStack → shared EpisodeQueueActions (same as mini ⋯ submenu).
            EpisodeQueueActions.menu(
                episode: episode,
                store: store,
                currentlyPlayingId: playback.currentEpisode?.id,
                queueLocked: settings.queueLocked,
                onRequestRemoveFromQueue: { episodePendingRemoveFromQueue = $0 }
            )

            // Remote-media only: skip local-folder `file://` (already on disk).
            // Shared with mini ⋯ via EpisodeDownloadActions.
            EpisodeDownloadActions.button(
                episode: episode,
                downloads: downloads,
                onRequestDeleteDownload: { episodePendingDeleteDownload = $0 }
            )

            // Shared with mini ⋯ via EpisodeOpenWebsite (http(s) link only).
            EpisodeOpenWebsite.button(episode: episode, openURL: openURL)

            if let url = episode.websiteURL {
                Button {
                    copyEpisodeLink(url)
                } label: {
                    Label("Copy episode link", systemImage: "doc.on.doc")
                }
                .accessibilityLabel(String(localized: "Copy episode link"))
                .accessibilityHint(String(localized: "Copies the episode webpage URL to the pasteboard"))
            }

            EpisodeShareLinks.episodeLinkLabelStyle(episode: episode)

            // Item podcast:socialInteract — Discuss opens highest-priority http(s) uri; hide when none.
            // Feed-provided only — never invent; openURL only (no Fediverse client / posting).
            if let interact = episode.preferredSocialInteract,
               let url = interact.discussionURL {
                Button {
                    openURL(url)
                } label: {
                    Label("Discuss", systemImage: "bubble.left.and.bubble.right")
                }
                .accessibilityLabel(String(localized: "Discuss"))
                .accessibilityHint(String(localized: "Opens the discussion link from the feed in the system browser"))
            }

            if let rawMediaURL = episode.mediaURLString {
                Button {
                    copyMediaURL(rawMediaURL)
                } label: {
                    Label("Copy media URL", systemImage: "link")
                }
                .accessibilityLabel(String(localized: "Copy media URL"))
                .accessibilityHint(String(localized: "Copies the episode media / enclosure URL to the pasteboard"))
            }

            // Share + Share with position (shared helper — same URL / text-timestamp rules as mini ⋯).
            EpisodeShareLinks.labelStyle(
                episode: episode,
                feed: feed,
                positionSeconds: playback.positionSeconds,
                feedDisplayTitle: feedDisplayTitle
            )
        }
        .buttonStyle(.bordered)
        .labelStyle(.titleAndIcon)
        .controlSize(.small)
    }

    /// Start a chapter load for the episode now playing. Cancels any previous load so
    /// its completion cannot write chapters onto a later episode.
    private func scheduleChapterLoad() {
        chapterLoadTask?.cancel()
        chapterLoadTask = Task { @MainActor in
            await loadChaptersIfNeeded()
        }
    }

    /// True while this load still belongs to the episode that started it.
    private func chapterLoadStillCurrent(episodeId: String) -> Bool {
        !Task.isCancelled && playback.currentEpisode?.id == episodeId
    }

    @MainActor
    private func loadChaptersIfNeeded() async {
        guard let resolved = resolvedEpisode else { return }
        let episodeId = resolved.id
        guard chapterLoadStillCurrent(episodeId: episodeId) else { return }

        // 1) Inline feed chapters (PSC) — prefer; skip remote + media.
        if !resolved.chapters.isEmpty {
            remoteChapters = []
            mediaChapters = []
            return
        }

        // 2) Podcast Index remote JSON when the feed only had a URL.
        if let url = resolved.podcastIndexChapterUrl, !url.isEmpty {
            isLoadingRemoteChapters = true
            defer {
                // A newer episode's load owns the spinner after this task is cancelled.
                if chapterLoadStillCurrent(episodeId: episodeId) {
                    isLoadingRemoteChapters = false
                }
            }
            do {
                let fetched = try await PodcastIndexChapterParser.fetch(urlString: url)
                if !fetched.isEmpty {
                    store.updateChapters(episodeId: episodeId, chapters: fetched)
                }
                // Episode changed or this load was cancelled while the request was in flight.
                // Keep the persisted chapters, but do not point Previous/Next at the old list.
                guard chapterLoadStillCurrent(episodeId: episodeId) else { return }
                if !fetched.isEmpty {
                    remoteChapters = fetched
                    mediaChapters = []
                    if var current = playback.currentEpisode, current.id == episodeId {
                        current.chapters = fetched
                        playback.currentEpisode = current
                    }
                    return
                }
                remoteChapters = []
            } catch {
                // Fall through to media-file chapters when local — only if still this episode.
                guard chapterLoadStillCurrent(episodeId: episodeId) else { return }
                remoteChapters = []
            }
        }

        guard chapterLoadStillCurrent(episodeId: episodeId) else { return }
        // 3) Local media-file tags (QuickTime/MP4 via AVFoundation) when feed has none.
        await loadMediaChaptersIfNeeded(for: resolved)
    }

    @MainActor
    private func loadMediaChaptersIfNeeded(for episode: PodcastEpisode) async {
        let episodeId = episode.id
        guard chapterLoadStillCurrent(episodeId: episodeId) else { return }
        guard playback.isPlayingFromLocalFile,
              let fileURL = downloads.localURL(for: episode) else {
            mediaChapters = []
            return
        }
        isLoadingMediaChapters = true
        defer {
            if chapterLoadStillCurrent(episodeId: episodeId) {
                isLoadingMediaChapters = false
            }
        }
        let loaded = await MediaFileChapterReader.chapters(fromFileURL: fileURL)
        guard chapterLoadStillCurrent(episodeId: episodeId) else { return }
        // Prefer feed if it appeared meanwhile (e.g. store refresh).
        if !(resolvedEpisode?.chapters.isEmpty ?? true) || !remoteChapters.isEmpty {
            mediaChapters = []
            return
        }
        mediaChapters = loaded
        if !loaded.isEmpty {
            store.updateChapters(episodeId: episodeId, chapters: loaded)
            if var current = playback.currentEpisode, current.id == episodeId {
                current.chapters = loaded
                playback.currentEpisode = current
            }
        }
    }

    /// Dismiss the player sheet, then deep-link to Subscriptions → Feed detail.
    private func openPodcastFromPlayer() {
        guard let feed else {
            showFeedUnavailable = true
            return
        }
        let id = feed.id
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NewEpisodeNotificationCoordinator.deepLink.openFeed(id: id)
        }
    }

    private func bookmarksAccessibilityValue(for episodeId: String) -> String {
        let count = store.bookmarkCount(for: episodeId)
        if count == 0 {
            return String(localized: "No bookmarks")
        }
        return String(localized: "\(count) bookmarks")
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else {
            return "--:--"
        }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// Remaining time with a leading minus (−m:ss or −h:mm:ss).
    private func formatRemaining(_ seconds: Double) -> String {
        guard seconds.isFinite else {
            return "--:--"
        }
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "-%d:%02d:%02d", h, m, s)
        }
        return String(format: "-%d:%02d", m, s)
    }
}
