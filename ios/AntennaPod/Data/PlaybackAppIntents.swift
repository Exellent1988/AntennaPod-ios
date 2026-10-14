import AppIntents
import Foundation

/// Lite Siri / Shortcuts: Play, Pause, Play/Pause (toggle), Skip Forward, Skip Back.
///
/// Uses `openAppWhenRun` and the same handlers as `antennapod://` URL schemes
/// (`play` / `pause` / `toggle` / `skip-forward` / `skip-back`).
/// Full in-process control without opening the UI would need App Groups / a shared store —
/// not wired in this beta. Discoverable via `AppShortcutsProvider` + Shortcuts app.
/// **Not** CarPlay templates, **not** episode/feed deep links beyond these playback actions.

struct TogglePlaybackAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Play/Pause"
    static var description: IntentDescription {
        IntentDescription(
            "Play or pause the loaded episode in AntennaPod, or after a cold launch start the previous run’s unplayed mini-player episode (opens the app)."
        )
    }
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            PlaybackDeepLinkRouter.shared.enqueue(.toggle)
        }
        return .result()
    }
}

struct PlayCurrentAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Play"
    static var description: IntentDescription {
        IntentDescription(
            "Resume the loaded episode in AntennaPod, or after a cold launch the previous run’s unplayed mini-player episode (opens the app)."
        )
    }
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            PlaybackDeepLinkRouter.shared.enqueue(.play)
        }
        return .result()
    }
}

struct PauseCurrentAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause"
    static var description: IntentDescription {
        IntentDescription(
            "Pause playback in AntennaPod (opens the app)."
        )
    }
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            PlaybackDeepLinkRouter.shared.enqueue(.pause)
        }
        return .result()
    }
}

struct SkipForwardAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Skip Forward"
    static var description: IntentDescription {
        IntentDescription(
            "Skip forward by the Settings fast-forward interval (opens the app)."
        )
    }
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            PlaybackDeepLinkRouter.shared.enqueue(.skipForward)
        }
        return .result()
    }
}

struct SkipBackAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Skip Back"
    static var description: IntentDescription {
        IntentDescription(
            "Skip back by the Settings rewind interval (opens the app)."
        )
    }
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            PlaybackDeepLinkRouter.shared.enqueue(.skipBack)
        }
        return .result()
    }
}

struct AntennaPodAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayCurrentAppIntent(),
            phrases: [
                "Play \(.applicationName)",
                "Resume \(.applicationName)",
                "Continue playing in \(.applicationName)"
            ],
            shortTitle: "Play",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: PauseCurrentAppIntent(),
            phrases: [
                "Pause \(.applicationName)",
                "Pause playback in \(.applicationName)"
            ],
            shortTitle: "Pause",
            systemImageName: "pause.fill"
        )
        AppShortcut(
            intent: TogglePlaybackAppIntent(),
            phrases: [
                "Play or pause \(.applicationName)",
                "Toggle playback in \(.applicationName)",
                "Pause or resume \(.applicationName)"
            ],
            shortTitle: "Play/Pause",
            systemImageName: "playpause.fill"
        )
        AppShortcut(
            intent: SkipForwardAppIntent(),
            phrases: [
                "Skip forward in \(.applicationName)",
                "Fast forward \(.applicationName)",
                "Skip ahead in \(.applicationName)"
            ],
            shortTitle: "Skip Forward",
            systemImageName: "goforward"
        )
        AppShortcut(
            intent: SkipBackAppIntent(),
            phrases: [
                "Skip back in \(.applicationName)",
                "Rewind \(.applicationName)",
                "Go back in \(.applicationName)"
            ],
            shortTitle: "Skip Back",
            systemImageName: "gobackward"
        )
    }
}
