import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var settings: AppSettings
    @State private var showFullPlayer = false

    var body: some View {
        if let episode = playback.currentEpisode {
            VStack(spacing: 8) {
                Button {
                    showFullPlayer = true
                } label: {
                    ProgressView(value: playback.durationSeconds > 0 ? playback.positionSeconds / playback.durationSeconds : 0)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open full player")
                .accessibilityHint("Shows the full player with scrubber and more controls")
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
                    .accessibilityLabel("Open full player, \(episode.title)")

                    Button {
                        playback.seek(bySeconds: -playback.rewindSeconds)
                    } label: {
                        Image(systemName: AppSettings.skipSystemImage(forward: false, seconds: settings.rewindSeconds))
                    }
                    .accessibilityLabel("Rewind \(settings.rewindSeconds) seconds")
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
                    .accessibilityLabel("Forward \(settings.fastForwardSeconds) seconds")
                    sleepTimerMenu
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
                            .font(.caption.monospacedDigit())
                    }
                    .accessibilityLabel("\(String(localized: "Playback speed")) \(String(format: "%.1f", playback.rate))")
                    .accessibilityHint("Chooses playback speed")
                }
            }
            .padding()
            .background(.bar)
            .sheet(isPresented: $showFullPlayer) {
                FullPlayerView()
            }
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
        } label: {
            if playback.isSleepTimerActive, let label = playback.sleepTimerStatusLabel {
                Text(label)
                    .font(.caption2.monospacedDigit())
                    .lineLimit(1)
            } else {
                Image(systemName: "moon.zzz")
            }
        }
        .accessibilityLabel(playback.isSleepTimerActive
            ? "\(String(localized: "Sleep timer")) \(playback.sleepTimerStatusLabel ?? "active")"
            : String(localized: "Sleep timer"))
        .accessibilityHint("Sets or turns off the sleep timer")
    }

    private var sourceIndicator: some View {
        Label(
            playback.isPlayingFromLocalFile ? "Local" : "Stream",
            systemImage: playback.isPlayingFromLocalFile ? "internaldrive" : "wifi"
        )
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .labelStyle(.titleAndIcon)
        .accessibilityLabel(playback.isPlayingFromLocalFile ? "Playing from download" : "Streaming")
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
