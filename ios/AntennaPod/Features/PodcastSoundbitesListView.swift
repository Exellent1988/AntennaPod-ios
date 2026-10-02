import SwiftUI
import UIKit

/// Feed-provided `podcast:soundbite` list — start/duration (+ optional title).
/// **Play soundbite** seeks to `startTime` and auto-pauses at `startTime + duration` via
/// `PlaybackService.playSoundbite` (same episode player — **not** a separate clip player).
/// Works for the current episode or starts playback when media is available; otherwise **Copy / Share soundbite details**.
/// Cap + honesty footnote.
struct PodcastSoundbitesListView: View {
    @EnvironmentObject private var playback: PlaybackService

    let soundbites: [PodcastSoundbite]
    /// Episode these soundbites belong to — Play uses this episode’s media / id.
    let episode: PodcastEpisode
    /// Section title (localized by caller).
    var title: String = String(localized: "Soundbites")

    @State private var showCopiedAlert = false
    @State private var copyFeedbackTick = 0

    private var capped: (shown: [PodcastSoundbite], truncated: Bool) {
        PodcastSoundbiteDisplay.capped(soundbites)
    }

    /// Play when enclosure or local file can resolve (PlaybackService gates Wi‑Fi / errors).
    private var canPlaySoundbite: Bool {
        if episode.downloadUrl.flatMap({ URL(string: $0) }) != nil {
            return true
        }
        if playback.downloads?.localURL(for: episode) != nil {
            return true
        }
        return false
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
                        localized: "Soundbites come from the feed. Play seeks to the start and pauses at the end of the clip in the episode player; there is no separate clip player."
                    )
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityLabel(
                    String(
                        localized: "Soundbites come from the feed. Play seeks to the start and pauses at the end of the clip in the episode player; there is no separate clip player."
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
                Text(String(localized: "Soundbite details copied to the pasteboard."))
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

            let detailsText = PodcastSoundbiteDisplay.copyText(bite)

            HStack(spacing: 12) {
                if canPlaySoundbite {
                    Button {
                        // RootTabView surfaces lastError when stream Wi‑Fi-only blocks.
                        _ = playback.playSoundbite(
                            episode: episode,
                            startTimeSeconds: bite.startTimeSeconds,
                            durationSeconds: bite.durationSeconds
                        )
                    } label: {
                        Label("Play soundbite", systemImage: "play.fill")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Play soundbite"))
                    .accessibilityHint(
                        String(
                            localized: "Plays this soundbite in the episode player from the start time and pauses at the end"
                        )
                    )
                }

                Button {
                    UIPasteboard.general.string = detailsText
                    copyFeedbackTick += 1
                    showCopiedAlert = true
                } label: {
                    Label("Copy soundbite details", systemImage: "doc.on.doc")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Copy soundbite details"))
                .accessibilityHint(
                    String(
                        localized: "Copies the displayed soundbite title and start/duration times to the pasteboard"
                    )
                )

                if !detailsText.isEmpty {
                    ShareLink(item: detailsText) {
                        Label("Share soundbite details", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share soundbite details"))
                    .accessibilityHint(
                        String(
                            localized: "Shares the displayed soundbite title and start/duration times as plain text"
                        )
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}
