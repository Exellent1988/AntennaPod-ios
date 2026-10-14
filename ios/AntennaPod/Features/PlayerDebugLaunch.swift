#if DEBUG
import Foundation
import UIKit

/// DEBUG-only launch hook for screenshots / UI checks of the full player.
///
/// `-APDebugPlayer YES` subscribes to a sample feed (`-APDebugFeedURL <url>` overrides),
/// loads its newest episode, seeks to `-APDebugPosition` seconds (default 754), pauses, and asks
/// the mini player to open the full player. `-APDebugLandscape YES` rotates to landscape. Not compiled into Release builds.
@MainActor
final class PlayerDebugLaunch: ObservableObject {
    static let shared = PlayerDebugLaunch()
    @Published private(set) var openFullPlayerToken = 0
    private var didRun = false

    static var isRequested: Bool { UserDefaults.standard.bool(forKey: "APDebugPlayer") }

    func runIfRequested(store: PodcastStore, playback: PlaybackService) {
        guard Self.isRequested, !didRun else { return }
        didRun = true
        let defaults = UserDefaults.standard
        let feedURL = defaults.string(forKey: "APDebugFeedURL") ?? "https://feeds.metaebene.me/freakshow/mp3"
        let position = defaults.object(forKey: "APDebugPosition") as? Double ?? 754
        Task { @MainActor in
            if !store.feeds.contains(where: { $0.feedUrl == feedURL }) {
                _ = await store.subscribe(feedUrl: feedURL)
            }
            guard let feed = store.feeds.first(where: { $0.feedUrl == feedURL }) ?? store.feeds.first,
                  let episode = feed.episodes.first(where: { ($0.downloadUrl ?? "").hasPrefix("http") })
            else { return }
            playback.play(episode: episode)
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            playback.seek(toSeconds: position)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if playback.isPlaying { playback.togglePlayPause() }
            openFullPlayerToken += 1
            // `-APDebugLandscape YES`: rotate for landscape screenshots (headless simulator).
            if defaults.bool(forKey: "APDebugLandscape"),
               let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { _ in }
            }
        }
    }
}
#endif
