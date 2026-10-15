#if DEBUG
import Foundation
import UIKit
import Combine

/// DEBUG-only launch hook for screenshots / UI checks of the full player.
///
/// `-APDebugPlayer YES` subscribes to a sample feed (`-APDebugFeedURL <url>` overrides),
/// loads its newest episode, seeks to `-APDebugPosition` seconds (default 754), pauses, and asks
/// the mini player to open the full player. `-APDebugLandscape YES` rotates to landscape. Not compiled into Release builds.
@MainActor
final class PlayerDebugLaunch: ObservableObject {
    static let shared = PlayerDebugLaunch()
    /// Fires once per request. A `@Published` counter replayed its last value to every new subscriber, so a
    /// re-created mini player re-opened the full player after a deep link had closed it.
    let openFullPlayer = PassthroughSubject<Void, Never>()
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
            openFullPlayer.send()
            // `-APDebugLandscape YES`: rotate for landscape screenshots (headless simulator).
            if defaults.bool(forKey: "APDebugLandscape"),
               let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { _ in }
            }
        }
    }

    /// Screenshots: scroll the list in the topmost presented sheet by `-APDebugScrollY <points>`.
    static func scrollPresentedList() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-APDebugScrollY"), i + 1 < args.count,
              let y = Double(args[i + 1]) else { return }
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        var top = window?.rootViewController
        while let next = top?.presentedViewController { top = next }
        func firstScroll(_ view: UIView) -> UIScrollView? {
            if let s = view as? UICollectionView ?? view as? UITableView { return s }
            for sub in view.subviews { if let s = firstScroll(sub) { return s } }
            return nil
        }
        guard let root = top?.view, let list = firstScroll(root) else { return }
        let maxY = max(0, list.contentSize.height - list.bounds.height + list.adjustedContentInset.bottom)
        list.setContentOffset(CGPoint(x: 0, y: min(y, maxY) - list.adjustedContentInset.top), animated: false)
    }
}
#endif
