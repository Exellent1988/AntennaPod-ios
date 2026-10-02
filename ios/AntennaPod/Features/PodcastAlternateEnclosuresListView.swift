import SwiftUI
import UIKit

/// Feed-provided `podcast:alternateEnclosure` / `podcast:source` list.
/// http(s) sources: **Play** (same episode via `PlaybackService.preferredMediaURL`) + **Open URL** + **Copy / Share**.
/// ipfs / magnet / other schemes: **Copy / Share** URI only — no invented playback.
/// Cap + honesty footnote (progress on episode id; downloads primary-URL keyed; no Lightning).
struct PodcastAlternateEnclosuresListView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var playback: PlaybackService

    let alternateEnclosures: [PodcastAlternateEnclosure]
    /// Episode these alternates belong to — Play keeps this id / metadata / queue / favorites.
    let episode: PodcastEpisode
    /// Section title (localized by caller).
    var title: String = String(localized: "Alternate media")

    @State private var showCopiedAlert = false
    @State private var copiedMessage = String(localized: "Media URL copied to the pasteboard.")
    @State private var copyFeedbackTick = 0

    private var capped: (shown: [PodcastAlternateEnclosure], truncated: Bool) {
        PodcastAlternateEnclosureDisplay.capped(alternateEnclosures)
    }

    var body: some View {
        let result = capped
        if !result.shown.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)

                ForEach(Array(result.shown.enumerated()), id: \.offset) { _, enclosure in
                    enclosureRow(enclosure)
                }

                Text(
                    String(
                        localized: "http(s) alternate sources can play this episode in the app. Progress and mark-as-played stay on the episode. Chapters or transcripts may not match an alternate bitrate. Downloads use the primary enclosure — playing an alternate streams unless the URLs match. ipfs and magnet stay Copy or Open only. Video-as-audio, proxy, and Wi‑Fi stream settings still apply."
                    )
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityLabel(
                    String(
                        localized: "http(s) alternate sources can play this episode in the app. Progress and mark-as-played stay on the episode. Chapters or transcripts may not match an alternate bitrate. Downloads use the primary enclosure — playing an alternate streams unless the URLs match. ipfs and magnet stay Copy or Open only. Video-as-audio, proxy, and Wi‑Fi stream settings still apply."
                    )
                )

                if result.truncated {
                    Text(String(localized: "Showing first 20 alternate media options from the feed."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(
                            String(localized: "Showing first 20 alternate media options from the feed.")
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
    private func enclosureRow(_ enclosure: PodcastAlternateEnclosure) -> some View {
        let headline = enclosure.displayTitle ?? enclosure.displayType ?? enclosure.type
        let bitrate = PodcastAlternateEnclosureDisplay.bitrateLabel(enclosure.bitrate)
        let captionParts: [String] = {
            var parts: [String] = []
            if enclosure.displayTitle != nil, let mime = enclosure.displayType {
                parts.append(mime)
            }
            if let bitrate {
                parts.append(bitrate)
            }
            if let len = PodcastAlternateEnclosureDisplay.lengthLabel(enclosure.length) {
                parts.append(len)
            }
            if let h = PodcastAlternateEnclosureDisplay.heightLabel(enclosure.height) {
                parts.append(h)
            }
            if let lang = PodcastAlternateEnclosureDisplay.languageLabel(enclosure.displayLang) {
                parts.append(lang)
            }
            if let rel = enclosure.displayRel {
                parts.append(rel)
            }
            if let codecs = enclosure.displayCodecs {
                parts.append(codecs)
            }
            return parts
        }()
        let a11y: String = {
            var parts: [String] = [String(localized: "Alternate media"), headline]
            if enclosure.markedDefault {
                parts.append(String(localized: "Default"))
            }
            parts.append(contentsOf: captionParts)
            return parts.joined(separator: ", ")
        }()

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "rectangle.stack.badge.play")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(headline)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if enclosure.markedDefault {
                    Text(String(localized: "Default"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(a11y)

            if !captionParts.isEmpty {
                Text(captionParts.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .accessibilityHidden(true)
            }

            ForEach(Array(enclosure.validSources.enumerated()), id: \.offset) { _, source in
                sourceRow(source)
            }

            if let bitrate {
                HStack(spacing: 12) {
                    Button {
                        copyToPasteboard(
                            bitrate,
                            confirmation: String(localized: "Bitrate copied to the pasteboard.")
                        )
                    } label: {
                        Label("Copy bitrate", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy bitrate"))
                    .accessibilityHint(
                        String(localized: "Copies the exact displayed alternate enclosure bitrate to the pasteboard")
                    )

                    ShareLink(item: bitrate) {
                        Label("Share bitrate", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share bitrate"))
                    .accessibilityHint(
                        String(localized: "Shares the exact displayed alternate enclosure bitrate as plain text")
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func sourceRow(_ source: PodcastAlternateSource) -> some View {
        let copyText = source.displayURI
        let playableURL = source.playableMediaURL

        if let uri = copyText {
            Text(uri)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
                .accessibilityLabel(String(localized: "Media URI \(uri)"))

            if let ct = source.displayContentType {
                Text(ct)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel(String(localized: "Content type \(ct)"))
            }
        }

        HStack(spacing: 12) {
            if let playableURL {
                Button {
                    // Same episode id; chosen http(s) URL for AVPlayer. RootTabView surfaces lastError
                    // (e.g. Wi‑Fi-only stream block). Resume / smart-mark stay on episode id.
                    _ = playback.play(episode: episode, preferredMediaURL: playableURL)
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Play"))
                .accessibilityHint(
                    String(
                        localized: "Plays this episode using the alternate http(s) media URL from the feed"
                    )
                )

                Button {
                    openURL(playableURL)
                } label: {
                    Label("Open URL", systemImage: "safari")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Open URL"))
                .accessibilityHint(
                    String(localized: "Opens this alternate media URL from the feed in the system browser")
                )
            }

            if let copyText, !copyText.isEmpty {
                Button {
                    copyToPasteboard(
                        copyText,
                        confirmation: String(localized: "Media URL copied to the pasteboard.")
                    )
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Copy"))
                .accessibilityHint(
                    String(
                        localized: "Copies the alternate media URI to the pasteboard. Only http(s) sources can play in the app."
                    )
                )

                Group {
                    if let playableURL {
                        ShareLink(item: playableURL) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .font(.subheadline)
                        }
                    } else {
                        ShareLink(item: copyText) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .font(.subheadline)
                        }
                    }
                }
                .accessibilityLabel(String(localized: "Share"))
                .accessibilityHint(
                    String(
                        localized: "Shares the alternate enclosure URL when it is a parseable http(s) URL; otherwise shares the same raw feed URI as Copy"
                    )
                )
            }
        }

        if let contentType = source.displayContentType {
            HStack(spacing: 12) {
                Button {
                    copyToPasteboard(
                        contentType,
                        confirmation: String(localized: "Content type copied to the pasteboard.")
                    )
                } label: {
                    Label("Copy content type", systemImage: "doc.on.doc")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Copy content type"))
                .accessibilityHint(
                    String(localized: "Copies the exact displayed alternate source content type to the pasteboard")
                )

                ShareLink(item: contentType) {
                    Label("Share content type", systemImage: "square.and.arrow.up")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Share content type"))
                .accessibilityHint(
                    String(localized: "Shares the exact displayed alternate source content type as plain text")
                )
            }
        }
    }

    private func copyToPasteboard(_ string: String, confirmation: String) {
        UIPasteboard.general.string = string
        copiedMessage = confirmation
        copyFeedbackTick &+= 1
        showCopiedAlert = true
    }
}
