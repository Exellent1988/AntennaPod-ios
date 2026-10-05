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
                guard playback.currentEpisode != nil else { return }
                playback.togglePlayPause()
            }
            .keyboardShortcut("p", modifiers: .command)

            Button("Skip Back") {
                guard playback.currentEpisode != nil else { return }
                playback.seek(bySeconds: -playback.rewindSeconds)
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)

            Button("Skip Forward") {
                guard playback.currentEpisode != nil else { return }
                playback.seek(bySeconds: playback.fastForwardSeconds)
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
        }
    }
}
