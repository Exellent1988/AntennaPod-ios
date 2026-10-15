import Foundation

/// Android `prefPauseForFocusLoss` (default **on**; no visible switch in current Android, the
/// upgrader forces it on): on → transient focus loss pauses and playback resumes on regain;
/// off → "can duck" losses lower the volume instead (Android: 25 %).
///
/// iOS has no focus requests; another app decides whether it interrupts or ducks us. The one
/// lever is the session mode: `.spokenAudio` lets spoken prompts (Maps navigation, Siri) pause
/// and then resume a podcast (`interruptSpokenAudioAndMixWithOthers`), while `.default` makes
/// those prompts duck it. Calls, alarms and other full interruptions always pause on iOS.
public enum InterruptionPolicy {
    public static let defaultPauseForInterruptions = true

    public enum SessionMode: Equatable, Sendable {
        case spokenAudio
        case moviePlayback
        case standard
    }

    /// - Parameters:
    ///   - volumeAdaptationOn: the speech mode Volume adaptation used to request.
    ///   - videoSurface: a video is shown (not audio-only).
    public static func sessionMode(pauseForInterruptions: Bool, volumeAdaptationOn: Bool, videoSurface: Bool) -> SessionMode {
        guard pauseForInterruptions else {
            // Duck: never spoken audio, or prompts would pause us again.
            return videoSurface ? .moviePlayback : .standard
        }
        if volumeAdaptationOn { return .spokenAudio }
        return videoSurface ? .moviePlayback : .spokenAudio
    }

    /// Resume when the interruption ends only if we were playing when it began, the system says
    /// resuming is appropriate (`.shouldResume`), and the user did not play / pause in between.
    public static func shouldResume(wasPlayingWhenBegan: Bool, systemShouldResume: Bool, userActedSince: Bool) -> Bool {
        wasPlayingWhenBegan && systemShouldResume && !userActedSince
    }
}
