import Foundation

/// URL actions for `antennapod://…` and Siri / App Shortcuts (lite).
enum AntennaPodURLAction: String, CaseIterable {
    case play
    case pause
    case toggle
    case skipForward = "skip-forward"
    case skipBack = "skip-back"

    var url: URL {
        URL(string: "antennapod://\(rawValue)")!
    }

    static func parse(url: URL) -> AntennaPodURLAction? {
        guard let scheme = url.scheme?.lowercased(), scheme == "antennapod" else {
            return nil
        }
        // antennapod://play → host; antennapod:///play or antennapod://play/ → path
        let host = url.host?.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased() ?? ""
        if let fromHost = AntennaPodURLAction(rawValue: host), !host.isEmpty {
            return fromHost
        }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        if let fromPath = AntennaPodURLAction(rawValue: path), !path.isEmpty {
            return fromPath
        }
        // Some handlers put the action in the first path component only.
        let first = path.split(separator: "/").first.map(String.init) ?? ""
        return AntennaPodURLAction(rawValue: first)
    }
}

/// Routes `antennapod://` URLs and App Intent actions to `PlaybackService`.
///
/// Intents open the app (`openAppWhenRun`); playback runs when an episode is loaded, or Play /
/// Toggle start the episode restored paused at a cold launch (`PlaybackService.restoredEpisode`).
/// No App Group / background audio control from Shortcuts when the process is cold without a
/// current item. Playback schemes only — not episode/feed deep links, not CarPlay templates.
/// Documented honestly in FEATURE-MATRIX / Settings / README.
@MainActor
final class PlaybackDeepLinkRouter: ObservableObject {
    static let shared = PlaybackDeepLinkRouter()

    weak var playback: PlaybackService?

    /// Action queued before `attach` (cold start from Shortcuts / URL).
    private var pending: AntennaPodURLAction?

    /// Last handled action (debug / Settings status).
    @Published private(set) var lastActionDescription: String?

    private init() {}

    func attach(playback: PlaybackService) {
        self.playback = playback
        if let pending {
            self.pending = nil
            apply(pending)
        }
    }

    @discardableResult
    func handle(url: URL) -> Bool {
        guard let action = AntennaPodURLAction.parse(url: url) else { return false }
        enqueue(action)
        return true
    }

    func enqueue(_ action: AntennaPodURLAction) {
        if playback != nil {
            apply(action)
        } else {
            pending = action
        }
    }

    func apply(_ action: AntennaPodURLAction) {
        guard let playback else {
            pending = action
            return
        }
        switch action {
        case .play:
            if playback.currentEpisode != nil, !playback.isPlaying {
                playback.togglePlayPause()
            } else if playback.currentEpisode == nil {
                // Cold launch: episode restored paused from the previous run (if any).
                playback.playRestoredEpisode()
            }
        case .pause:
            if playback.isPlaying {
                playback.togglePlayPause()
            }
        case .toggle:
            if playback.currentEpisode != nil {
                playback.togglePlayPause()
            } else {
                playback.playRestoredEpisode()
            }
        case .skipForward:
            if playback.currentEpisode != nil {
                playback.seek(bySeconds: playback.fastForwardSeconds)
            }
        case .skipBack:
            if playback.currentEpisode != nil {
                playback.seek(bySeconds: -playback.rewindSeconds)
            }
        }
        lastActionDescription = action.rawValue
    }
}
