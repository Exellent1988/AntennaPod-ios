import SwiftUI

/// Full-screen / sheet player opened from the mini player (AntennaPod P0).
struct FullPlayerView: View {
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var downloads: DownloadService
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var isScrubbing = false
    @State private var scrubSeconds: Double = 0
    /// Chapters loaded from Podcast Index JSON when the feed only had a URL.
    @State private var remoteChapters: [PodcastChapter] = []
    @State private var isLoadingRemoteChapters = false

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

    private var chapters: [PodcastChapter] {
        if !remoteChapters.isEmpty { return remoteChapters }
        return resolvedEpisode?.chapters ?? []
    }

    private var displayPosition: Double {
        isScrubbing ? scrubSeconds : playback.positionSeconds
    }

    private var currentChapterIndex: Int? {
        ChapterIndexing.currentIndex(in: chapters, at: displayPosition)
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
                    .accessibilityLabel("Close player")
                }
            }
        }
        .onAppear {
            scrubSeconds = playback.positionSeconds
            Task { await loadRemoteChaptersIfNeeded() }
        }
        .onChange(of: playback.currentEpisode?.id) { _, newId in
            if newId == nil {
                dismiss()
                return
            }
            scrubSeconds = playback.positionSeconds
            isScrubbing = false
            remoteChapters = []
            Task { await loadRemoteChaptersIfNeeded() }
        }
    }

    @ViewBuilder
    private func playerContent(episode: PodcastEpisode) -> some View {
        GeometryReader { geo in
            let side = min(geo.size.width - 48, 320)
            ScrollView {
                VStack(spacing: 24) {
                    artwork(side: side)
                        .padding(.top, 8)
                    VStack(spacing: 6) {
                        Text(episode.title)
                            .font(.title2.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                        Text(feed?.title ?? "Podcast")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Label(
                            playback.isPlayingFromLocalFile ? "Playing from download" : "Streaming",
                            systemImage: playback.isPlayingFromLocalFile ? "internaldrive" : "wifi"
                        )
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel(playback.isPlayingFromLocalFile ? "Playing from download" : "Streaming")
                    }
                    .padding(.horizontal)

                    scrubber
                        .padding(.horizontal)

                    transportControls
                        .padding(.horizontal)

                    secondaryActions(episode: episode)
                        .padding(.horizontal)

                    chaptersSection
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
        if isLoadingRemoteChapters && chapters.isEmpty {
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
            .accessibilityLabel("Playback position")
            HStack {
                Text(format(displayPosition))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(format(playback.durationSeconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var transportControls: some View {
        HStack(spacing: 28) {
            sleepTimerMenu
            Button {
                playback.seek(bySeconds: -PlaybackService.skipDeltaSeconds)
            } label: {
                Image(systemName: "gobackward.30")
                    .font(.title2)
            }
            .accessibilityLabel("Rewind 30 seconds")

            Button {
                playback.togglePlayPause()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
            }
            .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")

            Button {
                playback.seek(bySeconds: PlaybackService.skipDeltaSeconds)
            } label: {
                Image(systemName: "goforward.30")
                    .font(.title2)
            }
            .accessibilityLabel("Forward 30 seconds")

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
        } label: {
            Text(String(format: "%.1f×", playback.rate))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(minWidth: 44)
        }
        .accessibilityLabel("Playback speed \(String(format: "%.1f", playback.rate))")
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
            ? "Sleep timer \(playback.sleepTimerStatusLabel ?? "active")"
            : "Sleep timer")
    }

    private func secondaryActions(episode: PodcastEpisode) -> some View {
        let played = store.isPlayed(episode.id)
        return HStack(spacing: 16) {
            Button {
                store.togglePlayed(episode.id)
            } label: {
                Label(
                    played ? "Mark unplayed" : "Mark played",
                    systemImage: played ? "circle" : "checkmark.circle"
                )
            }

            Button {
                store.enqueue(episode)
            } label: {
                Label("Queue", systemImage: "text.append")
            }

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
        }
        .buttonStyle(.bordered)
        .labelStyle(.titleAndIcon)
        .controlSize(.small)
    }

    @MainActor
    private func loadRemoteChaptersIfNeeded() async {
        guard let resolved = resolvedEpisode else { return }
        if !resolved.chapters.isEmpty {
            remoteChapters = []
            return
        }
        guard let url = resolved.podcastIndexChapterUrl, !url.isEmpty else { return }
        isLoadingRemoteChapters = true
        defer { isLoadingRemoteChapters = false }
        do {
            let fetched = try await PodcastIndexChapterParser.fetch(urlString: url)
            remoteChapters = fetched
            store.updateChapters(episodeId: resolved.id, chapters: fetched)
            if var current = playback.currentEpisode, current.id == resolved.id {
                current.chapters = fetched
                playback.currentEpisode = current
            }
        } catch {
            // Keep section hidden on failure; feed may simply lack usable chapters.
            remoteChapters = []
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
}
