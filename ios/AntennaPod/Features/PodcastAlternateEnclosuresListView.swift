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
    @State private var copiedMessage = String(localized: "Alternate media URI copied to the pasteboard.")
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
        let title = enclosure.displayTitle
        let defaultLabel = enclosure.markedDefault ? String(localized: "Default") : nil
        let bitrate = PodcastAlternateEnclosureDisplay.bitrateLabel(enclosure.bitrate)
        let lengthLabel = PodcastAlternateEnclosureDisplay.lengthLabel(enclosure.length)
        let codecs = enclosure.displayCodecs
        let heightLabel = PodcastAlternateEnclosureDisplay.heightLabel(enclosure.height)
        let language = PodcastAlternateEnclosureDisplay.languageLabel(enclosure.displayLang)
        let captionParts: [String] = {
            var parts: [String] = []
            if enclosure.displayTitle != nil, let mime = enclosure.displayType {
                parts.append(mime)
            }
            if let bitrate {
                parts.append(bitrate)
            }
            if let lengthLabel {
                parts.append(lengthLabel)
            }
            if let heightLabel {
                parts.append(heightLabel)
            }
            if let language {
                parts.append(language)
            }
            if let rel = enclosure.displayRel {
                parts.append(rel)
            }
            if let codecs {
                parts.append(codecs)
            }
            return parts
        }()
        let a11y: String = {
            var parts: [String] = [String(localized: "Alternate media"), headline]
            if let defaultLabel {
                parts.append(defaultLabel)
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
                if let defaultLabel {
                    Text(defaultLabel)
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

            if let title {
                HStack(spacing: 12) {
                    Button {
                        copyToPasteboard(
                            title,
                            confirmation: String(localized: "Alternate media title copied to the pasteboard.")
                        )
                    } label: {
                        Label("Copy alternate media title", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy alternate media title"))
                    .accessibilityHint(
                        String(localized: "Copies the exact displayed alternate enclosure title to the pasteboard")
                    )

                    ShareLink(item: title) {
                        Label("Share alternate media title", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share alternate media title"))
                    .accessibilityHint(
                        String(localized: "Shares the exact displayed alternate enclosure title as plain text")
                    )
                }
            }

            if let defaultLabel {
                HStack(spacing: 12) {
                    Button {
                        copyToPasteboard(
                            defaultLabel,
                            confirmation: String(localized: "Alternate enclosure default copied to the pasteboard.")
                        )
                    } label: {
                        Label("Copy alternate enclosure default", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy alternate enclosure default"))
                    .accessibilityHint(
                        String(localized: "Copies the exact displayed Default label for this feed-provided alternate enclosure to the pasteboard")
                    )

                    ShareLink(item: defaultLabel) {
                        Label("Share alternate enclosure default", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share alternate enclosure default"))
                    .accessibilityHint(
                        String(localized: "Shares the exact displayed Default label for this feed-provided alternate enclosure as plain text")
                    )
                }
            }

            if let mediaType = enclosure.displayType {
                HStack(spacing: 12) {
                    Button {
                        copyToPasteboard(
                            mediaType,
                            confirmation: String(localized: "Alternate media type copied to the pasteboard.")
                        )
                    } label: {
                        Label("Copy alternate media type", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy alternate media type"))
                    .accessibilityHint(
                        String(localized: "Copies the exact displayed alternate enclosure media type to the pasteboard")
                    )

                    ShareLink(item: mediaType) {
                        Label("Share alternate media type", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share alternate media type"))
                    .accessibilityHint(
                        String(localized: "Shares the exact displayed alternate enclosure media type as plain text")
                    )
                }
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

            if let lengthLabel {
                HStack(spacing: 12) {
                    Button {
                        copyToPasteboard(
                            lengthLabel,
                            confirmation: String(localized: "Length copied to the pasteboard.")
                        )
                    } label: {
                        Label("Copy length", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy length"))
                    .accessibilityHint(
                        String(localized: "Copies the exact displayed alternate enclosure length to the pasteboard")
                    )

                    ShareLink(item: lengthLabel) {
                        Label("Share length", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share length"))
                    .accessibilityHint(
                        String(localized: "Shares the exact displayed alternate enclosure length as plain text")
                    )
                }
            }

            if let heightLabel {
                HStack(spacing: 12) {
                    Button {
                        copyToPasteboard(
                            heightLabel,
                            confirmation: String(localized: "Height copied to the pasteboard.")
                        )
                    } label: {
                        Label("Copy height", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy height"))
                    .accessibilityHint(
                        String(localized: "Copies the exact displayed alternate enclosure height to the pasteboard")
                    )

                    ShareLink(item: heightLabel) {
                        Label("Share height", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share height"))
                    .accessibilityHint(
                        String(localized: "Shares the exact displayed alternate enclosure height as plain text")
                    )
                }
            }

            if let relation = enclosure.displayRel {
                HStack(spacing: 12) {
                    Button {
                        copyToPasteboard(
                            relation,
                            confirmation: String(localized: "Alternate enclosure relation copied to the pasteboard.")
                        )
                    } label: {
                        Label("Copy relation", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy relation"))
                    .accessibilityHint(
                        String(localized: "Copies the exact displayed alternate enclosure relation to the pasteboard")
                    )

                    ShareLink(item: relation) {
                        Label("Share relation", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share relation"))
                    .accessibilityHint(
                        String(localized: "Shares the exact displayed alternate enclosure relation as plain text")
                    )
                }
            }

            if let codecs {
                HStack(spacing: 12) {
                    Button {
                        copyToPasteboard(
                            codecs,
                            confirmation: String(localized: "Codecs copied to the pasteboard.")
                        )
                    } label: {
                        Label("Copy codecs", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy codecs"))
                    .accessibilityHint(
                        String(localized: "Copies the exact displayed alternate enclosure codecs to the pasteboard")
                    )

                    ShareLink(item: codecs) {
                        Label("Share codecs", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share codecs"))
                    .accessibilityHint(
                        String(localized: "Shares the exact displayed alternate enclosure codecs as plain text")
                    )
                }
            }

            if let language {
                HStack(spacing: 12) {
                    Button {
                        copyToPasteboard(
                            language,
                            confirmation: String(localized: "Alternate enclosure language copied to the pasteboard.")
                        )
                    } label: {
                        Label("Copy language", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy language"))
                    .accessibilityHint(
                        String(localized: "Copies the exact displayed alternate enclosure language to the pasteboard")
                    )

                    ShareLink(item: language) {
                        Label("Share language", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share language"))
                    .accessibilityHint(
                        String(localized: "Shares the exact displayed alternate enclosure language as plain text")
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
                        confirmation: String(localized: "Alternate media URI copied to the pasteboard.")
                    )
                } label: {
                    Label("Copy alternate media URI", systemImage: "doc.on.doc")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Copy alternate media URI"))
                .accessibilityHint(
                    String(
                        localized: "Copies the exact displayed alternate media source URI to the pasteboard. Only http(s) sources can play in the app."
                    )
                )

                Group {
                    if let playableURL {
                        ShareLink(item: playableURL) {
                            Label("Share alternate media URI", systemImage: "square.and.arrow.up")
                                .font(.subheadline)
                        }
                    } else {
                        ShareLink(item: copyText) {
                            Label("Share alternate media URI", systemImage: "square.and.arrow.up")
                                .font(.subheadline)
                        }
                    }
                }
                .accessibilityLabel(String(localized: "Share alternate media URI"))
                .accessibilityHint(
                    String(
                        localized: "Shares the alternate media URL when it is a parseable http(s) URL; otherwise shares the same raw displayed feed URI as Copy"
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
