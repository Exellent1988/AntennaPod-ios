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
        return chapters.indices.filter { chapters[$0].title.localizedCaseInsensitiveContains(q) }
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
                        "Nothing playing",
                        systemImage: "play.slash",
                        description: Text("Start an episode from Inbox, Queue, or a feed.")
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
                        .accessibilityHint(
                            playback.pictureInPicture.isActive
                                ? String(localized: "Stops Picture in Picture")
                                : String(localized: "Starts Picture in Picture")
                        )
                    }
                }
            }
        }
        .onAppear {
            scrubSeconds = playback.positionSeconds
            Task { await loadChaptersIfNeeded() }
        }
        .onDisappear {
            chapterDebounceTask?.cancel()
        }
        .onChange(of: playback.currentEpisode?.id) { _, newId in
            playback.pictureInPicture.tearDown()
            if newId == nil {
                dismiss()
                return
            }
            scrubSeconds = playback.positionSeconds
            isScrubbing = false
            remoteChapters = []
            mediaChapters = []
            showTranscript = false
            showDescription = false
            resetChapterSearch()
            Task { await loadChaptersIfNeeded() }
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
                        Button {
                            openPodcastFromPlayer()
                        } label: {
                            Text(feedDisplayTitle ?? String(localized: "Podcast"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .buttonStyle(.plain)
                        .disabled(feed == nil)
                        .accessibilityLabel(String(localized: "Open podcast"))
                        .accessibilityValue(feedDisplayTitle ?? String(localized: "Podcast unavailable"))
                        .accessibilityHint(
                            feed == nil
                                ? String(localized: "Podcast unavailable")
                                : String(localized: "Opens this episode's podcast in Subscriptions")
                        )
                        // itunes:episodeType capsule when set — Full/Trailer/Bonus or raw; hide when missing (≠ channel podcast:trailer).
                        if let episodeType = episode.displayEpisodeType {
                            Text(episodeType)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                                .accessibilityLabel(episode.episodeTypeAccessibilityLabel ?? episodeType)
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
                            playback.isPlayingFromLocalFile ? "Playing from download" : "Streaming",
                            systemImage: playback.isPlayingFromLocalFile ? "internaldrive" : "wifi"
                        )
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel(playback.isPlayingFromLocalFile ? String(localized: "Playing from download") : String(localized: "Streaming"))
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
                                playback.seek(toSeconds: chapter.startTimeSeconds)
                                scrubSeconds = chapter.startTimeSeconds
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

    private func copyChaptersTOC() {
        let text = chaptersTOCPlain
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        copiedAlertMessage = String(localized: "Chapters copied to the pasteboard.")
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
                AsyncImage(url: chapterURL) { phase in
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
        if let urlString = preferredArtworkURLString, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
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
            .accessibilityValue(format(displayPosition))
            .accessibilityHint(String(localized: "Adjusts playback position"))
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
                .accessibilityHint(String(localized: "Toggles between remaining time and total duration"))
                .accessibilityValue(rightTimeLabel)
            }
        }
    }

    /// Right scrubber label: total duration, or −remaining when Show remaining time is on.
    /// When Remaining time respects speed is on, −remaining ÷ live session rate
    /// (fallback feed/default, 0.5…3.0); otherwise wall-clock.
    private var rightTimeLabel: String {
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
        playback.seek(toSeconds: seconds)
        scrubSeconds = seconds
        isScrubbing = false
    }

    private var transportControls: some View {
        HStack(spacing: 28) {
            sleepTimerMenu
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

            speedMenu
        }
        .buttonStyle(.plain)
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
                    Text("Active · \(label)")
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

    private func copyEpisodeLink(_ url: URL) {
        copiedAlertMessage = EpisodeCopyLinks.copyEpisodeLink(url)
        copyURLFeedbackTick += 1
        showCopiedAlert = true
    }

    private func copyMediaURL(_ url: URL) {
        copiedAlertMessage = EpisodeCopyLinks.copyMediaURL(url)
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
                store.togglePlayed(episode.id)
            } label: {
                Label(
                    played ? "Mark unplayed" : "Mark played",
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
                    favorited ? "Unfavorite" : "Favorite",
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
                    archived ? "Restore" : "Archive",
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

            if let url = episode.mediaURL {
                Button {
                    copyMediaURL(url)
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

    @MainActor
    private func loadChaptersIfNeeded() async {
        guard let resolved = resolvedEpisode else { return }

        // 1) Inline feed chapters (PSC) — prefer; skip remote + media.
        if !resolved.chapters.isEmpty {
            remoteChapters = []
            mediaChapters = []
            return
        }

        // 2) Podcast Index remote JSON when the feed only had a URL.
        if let url = resolved.podcastIndexChapterUrl, !url.isEmpty {
            isLoadingRemoteChapters = true
            defer { isLoadingRemoteChapters = false }
            do {
                let fetched = try await PodcastIndexChapterParser.fetch(urlString: url)
                if !fetched.isEmpty {
                    remoteChapters = fetched
                    mediaChapters = []
                    store.updateChapters(episodeId: resolved.id, chapters: fetched)
                    if var current = playback.currentEpisode, current.id == resolved.id {
                        current.chapters = fetched
                        playback.currentEpisode = current
                    }
                    return
                }
                remoteChapters = []
            } catch {
                // Fall through to media-file chapters when local.
                remoteChapters = []
            }
        }

        // 3) Local media-file tags (QuickTime/MP4 via AVFoundation) when feed has none.
        await loadMediaChaptersIfNeeded(for: resolved)
    }

    @MainActor
    private func loadMediaChaptersIfNeeded(for episode: PodcastEpisode) async {
        guard playback.isPlayingFromLocalFile,
              let fileURL = downloads.localURL(for: episode) else {
            mediaChapters = []
            return
        }
        isLoadingMediaChapters = true
        defer { isLoadingMediaChapters = false }
        let loaded = await MediaFileChapterReader.chapters(fromFileURL: fileURL)
        // Prefer feed if it appeared meanwhile (e.g. store refresh).
        if !(resolvedEpisode?.chapters.isEmpty ?? true) || !remoteChapters.isEmpty {
            mediaChapters = []
            return
        }
        mediaChapters = loaded
        if !loaded.isEmpty {
            store.updateChapters(episodeId: episode.id, chapters: loaded)
            if var current = playback.currentEpisode, current.id == episode.id {
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
