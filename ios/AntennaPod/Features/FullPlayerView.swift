import AVFoundation
import SwiftUI

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
    @State private var showJumpToPosition = false

    private var episode: PodcastEpisode? { playback.currentEpisode }

    private var feed: PodcastFeed? {
        guard let episode else { return nil }
        return store.feed(containingEpisodeId: episode.id)
    }

    /// Prefer store episode (post-refresh) over a possibly stale player/queue copy.
    private var resolvedEpisode: PodcastEpisode? {
        guard let episode else { return nil }
        return store.episode(id: episode.id) ?? episode
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

    private var canSkipChapters: Bool { !chapters.isEmpty }

    private var previousChapterTarget: Double? {
        ChapterIndexing.previousSeekSeconds(in: chapters, at: displayPosition)
    }

    private var nextChapterTarget: Double? {
        ChapterIndexing.nextSeekSeconds(in: chapters, at: displayPosition)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let episode {
                    playerContent(episode: episode)
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
                EpisodeDescriptionSheetView(episode: episode, feedTitle: feed?.title)
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
        .sheet(isPresented: $showCustomSleepTimer) {
            CustomSleepTimerSheet()
                .environmentObject(playback)
        }
        .sheet(isPresented: $showJumpToPosition) {
            JumpToPositionSheet(initialSeconds: displayPosition)
                .environmentObject(playback)
                .onDisappear {
                    scrubSeconds = playback.positionSeconds
                    isScrubbing = false
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
                            Text(feed?.title ?? String(localized: "Podcast"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .buttonStyle(.plain)
                        .disabled(feed == nil)
                        .accessibilityLabel(String(localized: "Open podcast"))
                        .accessibilityValue(feed?.title ?? String(localized: "Podcast unavailable"))
                        .accessibilityHint(
                            feed == nil
                                ? String(localized: "Podcast unavailable")
                                : String(localized: "Opens this episode's podcast in Subscriptions")
                        )
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

                    secondaryActions(episode: episode)
                        .padding(.horizontal)

                    chaptersSection
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
    private var chaptersSection: some View {
        if isLoadingChapters && chapters.isEmpty {
            HStack {
                ProgressView()
                Text("Loading chapters…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        } else if !chapters.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Chapters")
                    .font(.headline)
                ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                    Button {
                        playback.seek(toSeconds: chapter.startTimeSeconds)
                        scrubSeconds = chapter.startTimeSeconds
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(format(chapter.startTimeSeconds))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 44, alignment: .trailing)
                            Text(chapter.title)
                                .font(.subheadline.weight(index == currentChapterIndex ? .semibold : .regular))
                                .foregroundStyle(index == currentChapterIndex ? .primary : .secondary)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if index == currentChapterIndex {
                                Image(systemName: "waveform")
                                    .font(.caption)
                                    .foregroundStyle(.tint)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(index == currentChapterIndex ? Color.accentColor.opacity(0.12) : Color.clear)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Chapter \(chapter.title), \(format(chapter.startTimeSeconds))")
                    .accessibilityAddTraits(index == currentChapterIndex ? .isSelected : [])
                }
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // No chapters → hide section entirely (no empty placeholder).
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
            .accessibilityHint("Hides the video surface and shows artwork instead. Lockscreen stays audio.")
        }
    }

    @ViewBuilder
    private func artwork(side: CGFloat) -> some View {
        Group {
            if let urlString = feed?.imageUrl, let url = URL(string: urlString) {
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
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        .accessibilityHidden(true)
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
            .accessibilityHint("Adjusts playback position")
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
    private var rightTimeLabel: String {
        if settings.showRemainingTime {
            let remaining = playback.durationSeconds - displayPosition
            return formatRemaining(remaining)
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
            .accessibilityLabel("Rewind \(settings.rewindSeconds) seconds")

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
            .accessibilityLabel("Forward \(settings.fastForwardSeconds) seconds")

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
                        Text(String(format: "%.1f×", speed))
                        if speed == settings.defaultPlaybackSpeed {
                            Text("Default")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } primaryAction: {
            playback.cycleToNextSpeedPreset()
        } label: {
            Text(String(format: "%.1f×", playback.rate))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(minWidth: 44)
        }
        .accessibilityLabel("\(String(localized: "Playback speed")) \(String(format: "%.1f", playback.rate))")
        .accessibilityHint(String(localized: "Cycles to the next speed. Long-press for full list."))
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
            Button(String(localized: "Custom…")) {
                showCustomSleepTimer = true
            }
        } label: {
            if playback.isSleepTimerActive, let label = playback.sleepTimerStatusLabel {
                Text(label)
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 44)
            } else {
                Image(systemName: "moon.zzz")
                    .font(.title3)
                    .frame(minWidth: 44)
            }
        }
        .accessibilityLabel(playback.isSleepTimerActive
            ? "\(String(localized: "Sleep timer")) \(playback.sleepTimerStatusLabel ?? "active")"
            : String(localized: "Sleep timer"))
        .accessibilityHint("Sets or turns off the sleep timer")
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

            Button {
                store.playNext(episode, currentlyPlayingId: playback.currentEpisode?.id)
            } label: {
                Label("Play Next", systemImage: "text.insert")
            }
            .accessibilityLabel(String(localized: "Play Next"))

            Button {
                store.enqueue(episode)
            } label: {
                Label("Queue", systemImage: "text.append")
            }
            .accessibilityLabel(String(localized: "Queue"))

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
            .disabled(episode.downloadUrl == nil || downloads.inProgress.contains(episode.id))
            .accessibilityLabel(
                downloads.inProgress.contains(episode.id)
                    ? String(localized: "Downloading")
                    : downloads.isDownloaded(episode)
                        ? String(localized: "Downloaded")
                        : String(localized: "Download")
            )

            if let url = episode.websiteURL {
                Button {
                    openURL(url)
                } label: {
                    Label("Open episode website", systemImage: "safari")
                }
                .accessibilityLabel(String(localized: "Open episode website"))
                .accessibilityHint(String(localized: "Opens the episode webpage in the system browser"))
            }

            if let url = episode.shareURL(feed: feed) {
                ShareLink(
                    item: url,
                    subject: Text(episode.title),
                    message: Text(episode.shareMessage(feedTitle: feed?.title))
                ) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel(String(localized: "Share episode"))
                .accessibilityHint(String(localized: "Opens the system share sheet with the episode title and link"))
            }
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
