import SwiftUI
import UIKit

/// Feed-provided `podcast:soundbite` list — start/duration (+ optional title).
/// **Play soundbite** seeks to `startTime` and auto-pauses at `startTime + duration` via
/// `PlaybackService.playSoundbite` (same episode player — **not** a separate clip player).
/// Works for the current episode or starts playback when media is available; otherwise **Copy / Share soundbite details**.
/// Displayed feed start and duration captions have distinct **Copy / Share** actions; missing values are hidden.
/// When a feed title is displayed, distinct **Copy / Share soundbite title** (exact title only — never invent from time caption).
/// Cap + honesty footnote.
struct PodcastSoundbitesListView: View {
    @EnvironmentObject private var playback: PlaybackService

    let soundbites: [PodcastSoundbite]
    /// Episode these soundbites belong to — Play uses this episode’s media / id.
    let episode: PodcastEpisode
    /// Section title (localized by caller).
    var title: String = String(localized: "Soundbites")

    @State private var showCopiedAlert = false
    @State private var copiedMessage = String(localized: "Soundbite details copied to the pasteboard.")
    @State private var copyFeedbackTick = 0

    private var capped: (shown: [PodcastSoundbite], truncated: Bool) {
        PodcastSoundbiteDisplay.capped(soundbites)
    }

    /// Play when enclosure or local file can resolve (PlaybackService gates Wi‑Fi / errors).
    /// `URL(string:)` rejects a space in the enclosure, which hides Play soundbite for an
    /// undownloaded episode even though `PlaybackService.play` accepts that address.
    private var canPlaySoundbite: Bool {
        if EpisodeMediaURL.url(from: episode.downloadUrl) != nil {
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
                Text(copiedMessage)
            }
            .sensoryFeedback(.success, trigger: copyFeedbackTick)
        }
    }

    @ViewBuilder
    private func soundbiteRow(_ bite: PodcastSoundbite) -> some View {
        let headline = bite.displayTitle ?? String(localized: "Soundbite")
        let startCaption = PodcastSoundbiteDisplay.startCaption(bite)
        let durationCaption = PodcastSoundbiteDisplay.durationCaption(bite)
        let a11y: String = {
            var parts: [String] = [String(localized: "Soundbite")]
            if let t = bite.displayTitle {
                parts.append(t)
            }
            parts.append(startCaption)
            parts.append(durationCaption)
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

            VStack(alignment: .leading, spacing: 2) {
                Text(startCaption)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(durationCaption)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            let feedTitle = bite.displayTitle
            // Details match the displayed feed title and time captions exactly.
            let detailsText = PodcastSoundbiteDisplay.copyText(bite)

            HStack(spacing: 12) {
                Button {
                    copyToPasteboard(
                        startCaption,
                        confirmation: String(localized: "Soundbite start copied to the pasteboard.")
                    )
                } label: {
                    Label("Copy soundbite start", systemImage: "doc.on.doc")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Copy soundbite start"))
                .accessibilityHint(
                    String(localized: "Copies the exact displayed feed-provided soundbite start time as plain text")
                )

                ShareLink(item: startCaption) {
                    Label("Share soundbite start", systemImage: "square.and.arrow.up")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Share soundbite start"))
                .accessibilityHint(
                    String(localized: "Shares the exact displayed feed-provided soundbite start time as plain text")
                )
            }

            HStack(spacing: 12) {
                Button {
                    copyToPasteboard(
                        durationCaption,
                        confirmation: String(localized: "Soundbite duration copied to the pasteboard.")
                    )
                } label: {
                    Label("Copy soundbite duration", systemImage: "doc.on.doc")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Copy soundbite duration"))
                .accessibilityHint(
                    String(localized: "Copies the exact displayed feed-provided soundbite duration as plain text")
                )

                ShareLink(item: durationCaption) {
                    Label("Share soundbite duration", systemImage: "square.and.arrow.up")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Share soundbite duration"))
                .accessibilityHint(
                    String(localized: "Shares the exact displayed feed-provided soundbite duration as plain text")
                )
            }

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
                    copyToPasteboard(
                        detailsText,
                        confirmation: String(localized: "Soundbite details copied to the pasteboard.")
                    )
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

            if let feedTitle {
                HStack(spacing: 12) {
                    Button {
                        copyToPasteboard(
                            feedTitle,
                            confirmation: String(localized: "Soundbite title copied to the pasteboard.")
                        )
                    } label: {
                        Label("Copy soundbite title", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy soundbite title"))
                    .accessibilityHint(
                        String(
                            localized: "Copies the exact displayed feed-provided soundbite title to the pasteboard"
                        )
                    )

                    ShareLink(item: feedTitle) {
                        Label("Share soundbite title", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share soundbite title"))
                    .accessibilityHint(
                        String(
                            localized: "Shares the exact displayed feed-provided soundbite title as plain text"
                        )
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private func copyToPasteboard(_ string: String, confirmation: String) {
        UIPasteboard.general.string = string
        copiedMessage = confirmation
        copyFeedbackTick &+= 1
        showCopiedAlert = true
    }
}
