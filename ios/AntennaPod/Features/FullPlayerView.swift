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

    private var episode: PodcastEpisode? { playback.currentEpisode }

    private var feed: PodcastFeed? {
        guard let episode else { return nil }
        return store.feed(containingEpisodeId: episode.id)
    }

    private var displayPosition: Double {
        isScrubbing ? scrubSeconds : playback.positionSeconds
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
        }
        .onChange(of: playback.currentEpisode?.id) { _, newId in
            if newId == nil {
                dismiss()
                return
            }
            scrubSeconds = playback.positionSeconds
            isScrubbing = false
        }
    }

    @ViewBuilder
    private func playerContent(episode: PodcastEpisode) -> some View {
        GeometryReader { geo in
            let side = min(geo.size.width - 48, 320)
            VStack(spacing: 24) {
                Spacer(minLength: 8)
                artwork(side: side)
                VStack(spacing: 6) {
                    Text(episode.title)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    Text(feed?.title ?? "Podcast")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.horizontal)

                scrubber
                    .padding(.horizontal)

                transportControls
                    .padding(.horizontal)

                secondaryActions(episode: episode)
                    .padding(.horizontal)

                Spacer(minLength: 8)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .padding(.bottom, 16)
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
