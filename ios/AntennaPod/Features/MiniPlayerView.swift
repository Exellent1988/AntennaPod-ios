import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject private var playback: PlaybackService

    var body: some View {
        if let episode = playback.currentEpisode {
            VStack(spacing: 8) {
                ProgressView(value: playback.durationSeconds > 0 ? playback.positionSeconds / playback.durationSeconds : 0)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(episode.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(timeLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        playback.seek(bySeconds: -30)
                    } label: {
                        Image(systemName: "gobackward.30")
                    }
                    Button {
                        playback.togglePlayPause()
                    } label: {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    }
                    Button {
                        playback.seek(bySeconds: 30)
                    } label: {
                        Image(systemName: "goforward.30")
                    }
                    Menu {
                        ForEach([0.8, 1.0, 1.2, 1.5, 2.0], id: \.self) { rate in
                            Button("\(rate, specifier: "%.1f")×") {
                                playback.setRate(Float(rate))
                            }
                        }
                    } label: {
                        Text("\(playback.rate, specifier: "%.1f")×")
                            .font(.caption.monospacedDigit())
                    }
                }
            }
            .padding()
            .background(.bar)
        }
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
