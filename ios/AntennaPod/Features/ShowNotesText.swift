import PodcastCore
import SwiftUI

/// Show notes paragraph with tappable links and timestamps (Android `ShownotesCleaner`).
/// A timestamp seeks only when this episode is the one loaded in the player, like Android;
/// otherwise it explains that the episode has to be played first.
struct ShowNotesText: View {
    let text: String
    let episode: PodcastEpisode
    var anchors: [(text: String, href: String)] = []
    @EnvironmentObject private var playback: PlaybackService
    @Environment(\.openURL) private var openURL
    @State private var showPlayFirst = false

    var body: some View {
        Text(Self.attributed(text, anchors: anchors, duration: episode.durationSeconds))
            .environment(\.openURL, OpenURLAction { url in
                if let secs = Self.seekSeconds(from: url) {
                    if !Self.seek(to: secs, episode: episode, playback: playback) { showPlayFirst = true }
                    return .handled
                }
                return .systemAction
            })
            .alert(String(localized: "Play this episode to jump to positions"), isPresented: $showPlayFirst) {
                Button("OK", role: .cancel) {}
            }
    }

    static let seekScheme = "antennapod-seek"

    static func attributed(_ text: String, anchors: [(text: String, href: String)], duration: Double) -> AttributedString {
        var out = AttributedString()
        for run in ShowNotesLinks.runs(text, anchors: anchors, durationSeconds: duration > 0 ? duration : nil) {
            var part = AttributedString(run.text)
            switch run.kind {
            case .url(let s): part.link = URL(string: s)
            case .timestamp(let secs): part.link = URL(string: "\(seekScheme):\(secs)")
            case nil: break
            }
            out += part
        }
        return out
    }

    static func seekSeconds(from url: URL) -> Int? {
        guard url.scheme == seekScheme else { return nil }
        return Int(url.absoluteString.dropFirst(seekScheme.count + 1))
    }

    /// Seeks when `episode` is loaded in the player; returns false otherwise (Android shows a hint).
    @MainActor
    @discardableResult
    static func seek(to seconds: Int, episode: PodcastEpisode, playback: PlaybackService) -> Bool {
        guard playback.currentEpisode?.id == episode.id else { return false }
        playback.seek(toSeconds: Double(seconds))
        return true
    }
}

/// Android audio player pager: swipe between the cover and the show notes.
struct PlayerCoverNotesPager<Cover: View>: View {
    let side: CGFloat
    let episode: PodcastEpisode?
    @ViewBuilder let cover: () -> Cover
    @State private var page = 0

    var body: some View {
        if let episode, let raw = episode.descriptionText, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            TabView(selection: $page) {
                cover().tag(0)
                ScrollView {
                    ShowNotesText(text: HTMLTextStripping.plainText(from: raw), episode: episode,
                                  anchors: ShowNotesLinks.anchors(inHTML: raw))
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .tag(1)
                .accessibilityLabel(String(localized: "Shownotes"))
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))
            .frame(width: side, height: side + 28)
            .accessibilityIdentifier("playerCoverNotesPager")
            .accessibilityHint(String(localized: "Swipe left for the shownotes, right for the cover."))
            #if DEBUG
            .onAppear { if UserDefaults.standard.integer(forKey: "APDebugPlayerPage") == 1 { page = 1 } }
            #endif
        } else {
            cover()
        }
    }
}

/// Android player share menu extras: media file (downloaded) and feed URL.
struct PlayerShareExtras: View {
    let episode: PodcastEpisode
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var downloads: DownloadService

    var body: some View {
        if let file = Self.localFile(for: episode, downloads: downloads) {
            ShareLink(item: file) {
                Label(String(localized: "Share media file"), systemImage: "square.and.arrow.up.on.square")
            }
            .accessibilityHint(String(localized: "Shares the downloaded audio or video file itself."))
        }
        if let feedURL = Self.feedURL(for: episode, store: store) {
            ShareLink(item: feedURL) {
                Label(String(localized: "Share feed URL"), systemImage: "dot.radiowaves.up.forward")
            }
            .accessibilityHint(String(localized: "Shares the podcast's RSS feed address."))
        }
    }

    @MainActor
    static func localFile(for episode: PodcastEpisode, downloads: DownloadService) -> URL? {
        guard let d = downloads.downloads.first(where: { $0.id == episode.id }),
              FileManager.default.fileExists(atPath: d.localFileURL.path) else { return nil }
        return d.localFileURL
    }

    @MainActor
    static func feedURL(for episode: PodcastEpisode, store: PodcastStore) -> URL? {
        guard let s = store.feed(containingEpisodeId: episode.id)?.feedUrl,
              let url = URL(string: s), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }
}
