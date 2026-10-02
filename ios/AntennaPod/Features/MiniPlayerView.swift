import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: PodcastStore
    @State private var showFullPlayer = false
    @State private var showFeedUnavailable = false
    @State private var showCustomSleepTimer = false
    @State private var showCustomPlaybackSpeed = false
    @State private var showBookmarks = false
    @State private var showJumpToPosition = false
    @State private var showDescription = false

    var body: some View {
        if let episode = playback.currentEpisode {
            VStack(spacing: 8) {
                Button {
                    showFullPlayer = true
                } label: {
                    ProgressView(value: playback.durationSeconds > 0 ? playback.positionSeconds / playback.durationSeconds : 0)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Open full player"))
                .accessibilityHint(String(localized: "Shows the full player with scrubber and more controls"))
                .accessibilityValue(timeLabel)

                HStack {
                    Button {
                        showFullPlayer = true
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(episode.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                            if let chapterTitle = currentChapterTitle {
                                Text(chapterTitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            HStack(spacing: 6) {
                                Text(timeLabel)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                sourceIndicator
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(openFullPlayerAccessibilityLabel(for: episode))

                    Button {
                        playback.seek(bySeconds: -playback.rewindSeconds)
                    } label: {
                        Image(systemName: AppSettings.skipSystemImage(forward: false, seconds: settings.rewindSeconds))
                    }
                    .accessibilityLabel(String(localized: "Rewind \(settings.rewindSeconds) seconds"))
                    Button {
                        playback.togglePlayPause()
                    } label: {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .accessibilityLabel(playback.isPlaying ? String(localized: "Pause") : String(localized: "Play"))
                    Button {
                        playback.seek(bySeconds: playback.fastForwardSeconds)
                    } label: {
                        Image(systemName: AppSettings.skipSystemImage(forward: true, seconds: settings.fastForwardSeconds))
                    }
                    .accessibilityLabel(String(localized: "Forward \(settings.fastForwardSeconds) seconds"))
                    sleepTimerMenu
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
                            .font(.caption.monospacedDigit())
                    }
                    .accessibilityLabel("\(String(localized: "Playback speed")) \(PlaybackService.formatPlaybackSpeed(playback.rate))")
                    .accessibilityHint(String(localized: "Cycles to the next speed. Long-press for full list and Custom…"))

                    Menu {
                        Button {
                            openPodcastFromMiniPlayer()
                        } label: {
                            Label("Open podcast", systemImage: "dot.radiowaves.left.and.right")
                        }
                        .disabled(feedForCurrentEpisode == nil)
                        Button {
                            showDescription = true
                        } label: {
                            Label("Shownotes", systemImage: "doc.text")
                        }
                        .accessibilityLabel(String(localized: "Show shownotes"))
                        .accessibilityHint(
                            episode.hasDescriptionText
                                ? String(localized: "Opens the episode description from the feed")
                                : String(localized: "No description available for this episode")
                        )
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
                        .accessibilityHint(String(localized: "Lists bookmarks for this episode and saves the current position"))
                        Button {
                            showJumpToPosition = true
                        } label: {
                            Label("Jump to position", systemImage: "arrow.right.to.line")
                        }
                        .disabled(!canJumpToPosition)
                        .accessibilityHint(
                            canJumpToPosition
                                ? String(localized: "Enter a time to seek")
                                : String(localized: "Duration unknown — jump unavailable.")
                        )
                        // Current episode only (mini always shows current). Hidden when nothing shareable.
                        EpisodeShareLinks.labelStyle(
                            episode: episode,
                            feed: feedForCurrentEpisode,
                            positionSeconds: playback.positionSeconds
                        )
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel(String(localized: "Player options"))
                }
            }
            .padding()
            .background(.bar)
            .sheet(isPresented: $showFullPlayer) {
                FullPlayerView()
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
                CustomSleepTimerSheet(initialMinutes: settings.lastCustomSleepTimerMinutes)
                    .environmentObject(playback)
                    .environmentObject(settings)
            }
            .sheet(isPresented: $showCustomPlaybackSpeed) {
                CustomPlaybackSpeedSheet(mode: .session, initialSpeed: playback.rate)
                    .environmentObject(playback)
                    .environmentObject(settings)
            }
            .sheet(isPresented: $showBookmarks) {
                EpisodeBookmarksSheet(episodeId: episode.id)
                    .environmentObject(playback)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showJumpToPosition) {
                JumpToPositionSheet(initialSeconds: playback.positionSeconds)
                    .environmentObject(playback)
            }
            .sheet(isPresented: $showDescription) {
                // Prefer store episode (post-refresh) over a possibly stale player copy — same as Full.
                EpisodeDescriptionSheetView(
                    episode: store.episode(id: episode.id) ?? episode,
                    feedTitle: feedForCurrentEpisode?.title
                )
            }
        }
    }

    /// Same gate as FullPlayerView: known finite duration and a current episode.
    private var canJumpToPosition: Bool {
        playback.currentEpisode != nil
            && playback.durationSeconds.isFinite
            && playback.durationSeconds > 0
    }

    /// Chapters already on the store/player episode (PSC / persisted Podcast Index / media).
    /// Mini player does not fetch remote or media chapters — Full Player does that lazily.
    private var chapters: [PodcastChapter] {
        guard let episode = playback.currentEpisode else { return [] }
        let resolved = store.episode(id: episode.id) ?? episode
        return resolved.chapters
    }

    /// Title of the chapter at `positionSeconds`, or `nil` when none / empty title.
    private var currentChapterTitle: String? {
        guard let index = ChapterIndexing.currentIndex(in: chapters, at: playback.positionSeconds) else {
            return nil
        }
        let title = chapters[index].title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private func openFullPlayerAccessibilityLabel(for episode: PodcastEpisode) -> String {
        if let chapter = currentChapterTitle {
            return String(localized: "Open full player, \(episode.title), chapter \(chapter)")
        }
        return String(localized: "Open full player, \(episode.title)")
    }

    private var feedForCurrentEpisode: PodcastFeed? {
        guard let episode = playback.currentEpisode else { return nil }
        return store.feed(containingEpisodeId: episode.id)
    }

    private func openPodcastFromMiniPlayer() {
        guard let feed = feedForCurrentEpisode else {
            showFeedUnavailable = true
            return
        }
        // Close full player sheet if open, then navigate.
        showFullPlayer = false
        let id = feed.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NewEpisodeNotificationCoordinator.deepLink.openFeed(id: id)
        }
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
            HStack(spacing: 4) {
                Image(systemName: "moon.zzz")
                if playback.isSleepTimerActive, let label = playback.sleepTimerStatusLabel {
                    Text(label)
                        .font(.caption2.monospacedDigit())
                        .lineLimit(1)
                }
            }
        }
        .accessibilityLabel(playback.sleepTimerAccessibilityLabel)
        .accessibilityHint(String(localized: "Sets or turns off the sleep timer"))
    }

    private var sourceIndicator: some View {
        Label(
            playback.isPlayingFromLocalFile ? "Local" : "Stream",
            systemImage: playback.isPlayingFromLocalFile ? "internaldrive" : "wifi"
        )
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .labelStyle(.titleAndIcon)
        .accessibilityLabel(playback.isPlayingFromLocalFile ? String(localized: "Playing from download") : String(localized: "Streaming"))
    }

    private var timeLabel: String {
        "\(format(playback.positionSeconds)) / \(rightTimeLabel)"
    }

    /// Duration, or −remaining when Settings → Show remaining time is on.
    private var rightTimeLabel: String {
        if settings.showRemainingTime {
            return formatRemaining(playback.durationSeconds - playback.positionSeconds)
        }
        return format(playback.durationSeconds)
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite else {
            return "--:--"
        }
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Remaining time with a leading minus (−m:ss).
    private func formatRemaining(_ seconds: Double) -> String {
        guard seconds.isFinite else {
            return "--:--"
        }
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "-%d:%02d", total / 60, total % 60)
    }
}
