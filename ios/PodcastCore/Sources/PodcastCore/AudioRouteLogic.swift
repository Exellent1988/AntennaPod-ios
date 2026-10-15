import Foundation

/// Kind of audio output for Android's separate "Headphones reconnect" / "Bluetooth reconnect"
/// settings. Built from `AVAudioSession.Port` raw values so the logic stays testable.
public enum AudioRouteKind: Equatable, Sendable {
    case wired
    case bluetooth
    case other

    /// Wired: headphones, line out, USB audio. Bluetooth: A2DP, LE, HFP. Speaker, AirPlay,
    /// CarPlay / car audio, HDMI → other (never auto-resumes).
    public static func kind(ofOutputPorts ports: [String]) -> AudioRouteKind {
        if ports.contains(where: { bluetoothPorts.contains($0) }) { return .bluetooth }
        if ports.contains(where: { wiredPorts.contains($0) }) { return .wired }
        return .other
    }

    public static let wiredPorts: Set<String> = ["Headphones", "LineOut", "USBAudio"]
    public static let bluetoothPorts: Set<String> = ["BluetoothA2DPOutput", "BluetoothLE", "BluetoothHFP"]
}

/// Android `PlaybackService.unpauseIfPauseOnDisconnect`: resume only when *we* paused because
/// the headset / Bluetooth device went away (`transientPause`), the matching setting is on, and
/// nothing else happened in between. Android has no time limit; iOS adds one so a device that
/// reconnects hours later does not start audio unexpectedly.
public enum ReconnectResumePolicy {
    /// Defaults match Android: headphones on, Bluetooth off.
    public static let defaultResumeOnHeadphones = true
    public static let defaultResumeOnBluetooth = false
    /// iOS-only safety window between the unplug pause and the reconnect.
    public static let resumeWindowSeconds: TimeInterval = 30 * 60

    public static func shouldResume(
        pausedByUnplugAt: Date?,
        now: Date,
        newRoute: AudioRouteKind,
        resumeOnHeadphones: Bool,
        resumeOnBluetooth: Bool,
        window: TimeInterval = resumeWindowSeconds
    ) -> Bool {
        guard let pausedAt = pausedByUnplugAt else { return false }
        let elapsed = now.timeIntervalSince(pausedAt)
        guard elapsed >= 0, elapsed <= window else { return false }
        switch newRoute {
        case .wired: return resumeOnHeadphones
        case .bluetooth: return resumeOnBluetooth
        case .other: return false
        }
    }
}
