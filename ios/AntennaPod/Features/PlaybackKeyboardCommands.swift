import SwiftUI

/// Hardware keyboard shortcuts (iPad / Magic Keyboard), listed in the Cmd-hold HUD / menu bar.
/// Same `PlaybackService` calls as the lock-screen remote commands, so failed-stream rebuild
/// and the configured skip intervals apply. No-ops when nothing is loaded.
///
/// Play/Pause is Cmd+P, not bare Space: a Space key command could compete with typing in a
/// search field. Cmd+Left / Cmd+Right are arrow-key commands, which UIKit gives lower priority
/// than text navigation, so a focused text field still moves its cursor.
/// `playback` is not observed on purpose: it publishes every 0.5s while playing.
struct PlaybackKeyboardCommands: Commands {
    let playback: PlaybackService

    var body: some Commands {
        CommandMenu("Playback") {
            Button("Play/Pause") {
                // togglePlayPause also starts an episode restored paused at launch.
                guard playback.currentEpisode != nil || playback.restoredEpisode != nil else { return }
                playback.togglePlayPause()
            }
            .keyboardShortcut("p", modifiers: .command)
            .accessibilityHint(String(localized: "Toggles play or pause for the loaded episode, or starts a cold-launch restored episode. Does nothing when nothing is loaded or restored. Same path as Lock Screen and Now Playing remotes. Not bare Space, so typing in search fields stays unaffected."))

            Button("Skip Back") {
                guard playback.currentEpisode != nil else { return }
                playback.seek(bySeconds: -playback.rewindSeconds)
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .accessibilityHint(String(localized: "Seeks backward by the Settings Rewind interval. Does nothing when no episode is loaded. Same path as Lock Screen and Now Playing remotes. Not Continuous playback, and it does not invent a previous episode."))

            Button("Skip Forward") {
                guard playback.currentEpisode != nil else { return }
                playback.seek(bySeconds: playback.fastForwardSeconds)
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .accessibilityHint(String(localized: "Seeks forward by the Settings Fast-forward interval. Does nothing when no episode is loaded. Same path as Lock Screen and Now Playing remotes. A seek that reaches a known duration finishes playback like playing to the end."))
        }
    }
}
