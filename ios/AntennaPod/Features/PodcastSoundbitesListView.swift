import SwiftUI
import UIKit

/// Feed-provided `podcast:soundbite` list — start/duration (+ optional title).
/// When `episodeId` matches the current `PlaybackService` episode, tap seeks to startTime.
/// Otherwise shows times + **Copy** (no separate clip player). Cap + honesty footnote.
struct PodcastSoundbitesListView: View {
    @EnvironmentObject private var playback: PlaybackService

    let soundbites: [PodcastSoundbite]
    /// Episode these soundbites belong to — seek only when it is the current playback item.
    let episodeId: String
    /// Section title (localized by caller).
    var title: String = String(localized: "Soundbites")

    @State private var showCopiedAlert = false
    @State private var copyFeedbackTick = 0

    private var capped: (shown: [PodcastSoundbite], truncated: Bool) {
        PodcastSoundbiteDisplay.capped(soundbites)
    }

    /// Seek only when this episode is loaded as the current PlaybackService item (existing seek API).
    private var canSeek: Bool {
        playback.currentEpisode?.id == episodeId
    }

    var body: some View {
        let result = capped
        if !result.shown.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)

                ForEach(Array(result.shown.enumerated()), id: \.offset) { _, bite in
                    soundbiteRow(bite)
                }

                Text(
                    String(
                        localized: "Soundbites come from the feed. Tapping seeks in the current episode when it is playing; there is no separate clip player."
                    )
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityLabel(
                    String(
                        localized: "Soundbites come from the feed. Tapping seeks in the current episode when it is playing; there is no separate clip player."
                    )
                )

                if result.truncated {
                    Text(String(localized: "Showing first 20 soundbites from the feed."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(
                            String(localized: "Showing first 20 soundbites from the feed.")
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .alert(String(localized: "Copied"), isPresented: $showCopiedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(String(localized: "Soundbite copied to the pasteboard."))
            }
            .sensoryFeedback(.success, trigger: copyFeedbackTick)
        }
    }

    @ViewBuilder
    private func soundbiteRow(_ bite: PodcastSoundbite) -> some View {
        let headline = bite.displayTitle ?? PodcastSoundbiteDisplay.timeCaption(bite)
        let caption = PodcastSoundbiteDisplay.timeCaption(bite)
        let startLabel = PodcastSoundbiteDisplay.formatSeconds(bite.startTimeSeconds)
        let durationLabel = PodcastSoundbiteDisplay.formatSeconds(bite.durationSeconds)
        let a11y: String = {
            var parts: [String] = [String(localized: "Soundbite")]
            if let t = bite.displayTitle {
                parts.append(t)
            }
            parts.append(String(localized: "Start \(startLabel)"))
            parts.append(String(localized: "Duration \(durationLabel)"))
            return parts.joined(separator: ", ")
        }()

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "quote.bubble")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(headline)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(a11y)

            if bite.displayTitle != nil {
                Text(caption)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            if canSeek {
                Button {
                    playback.seek(toSeconds: bite.startTimeSeconds)
                } label: {
                    Label("Seek to start", systemImage: "goforward")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Seek to start"))
                .accessibilityHint(
                    String(localized: "Seeks playback to the soundbite start time in the current episode")
                )
            } else {
                Button {
                    UIPasteboard.general.string = PodcastSoundbiteDisplay.copyText(bite)
                    copyFeedbackTick += 1
                    showCopiedAlert = true
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Copy"))
                .accessibilityHint(
                    String(
                        localized: "Copies the soundbite title and times to the pasteboard. Seek is available when this episode is playing."
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}
