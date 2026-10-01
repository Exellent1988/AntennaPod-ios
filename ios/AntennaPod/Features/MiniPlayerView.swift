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
                        playback.seek(bySeconds: -PlaybackService.skipDeltaSeconds)
                    } label: {
                        Image(systemName: "gobackward.30")
                    }
                    Button {
                        playback.togglePlayPause()
                    } label: {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    }
                    Button {
                        playback.seek(bySeconds: PlaybackService.skipDeltaSeconds)
                    } label: {
                        Image(systemName: "goforward.30")
                    }
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
            ? "Sleep timer \(playback.sleepTimerStatusLabel ?? "active")"
            : "Sleep timer")
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
        "\(format(playback.positionSeconds)) / \(format(playback.durationSeconds))"
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite else {
            return "--:--"
        }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
