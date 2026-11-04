import Foundation

/// Pure skip-silence decision logic (no AVFoundation).
///
/// Android AntennaPod uses ExoPlayer's `SilenceSkippingAudioProcessor`, which drops silent PCM.
/// AVPlayer taps cannot drop frames, so iOS speeds playback up while the signal stays below
/// `thresholdDB` for at least `minimumSilence`, and returns to the user's speed as soon as sound
/// is back. Hysteresis (`releaseDB`) keeps breaths / room tone from flapping the state.
public struct SilenceDetector: Sendable {
    public var thresholdDB: Double
    public var releaseDB: Double
    public var minimumSilence: Double

    public private(set) var silentDuration: Double = 0
    public private(set) var isSkipping = false

    public init(thresholdDB: Double = -45, releaseDB: Double = -40, minimumSilence: Double = 0.3) {
        self.thresholdDB = thresholdDB
        self.releaseDB = max(releaseDB, thresholdDB)
        self.minimumSilence = minimumSilence
    }

    /// Feed one analysed block (level + duration). Returns `true` when `isSkipping` changed.
    @discardableResult
    public mutating func feed(levelDB: Double, duration: Double) -> Bool {
        let was = isSkipping
        if isSkipping {
            if levelDB > releaseDB {
                isSkipping = false
                silentDuration = 0
            } else {
                silentDuration += duration
            }
        } else if levelDB < thresholdDB {
            silentDuration += duration
            if silentDuration >= minimumSilence { isSkipping = true }
        } else {
            silentDuration = 0
        }
        return was != isSkipping
    }

    public mutating func reset() {
        silentDuration = 0
        isSkipping = false
    }
}

/// Rate math for skip silence.
public enum SkipSilenceRate {
    /// Multiplier applied on top of the user's speed while in silence.
    public static let silenceSpeedup: Float = 3

    /// Player rate to use: base speed normally; during silence base × speedup, capped at `maxRate`
    /// (never below base).
    public static func effectiveRate(base: Float, isSkipping: Bool, maxRate: Float) -> Float {
        guard isSkipping else { return base }
        return max(base, min(base * silenceSpeedup, maxRate))
    }

    /// Wall-clock seconds saved while `mediaSeconds` of audio played at `fastRate` instead of `base`.
    public static func timeSaved(mediaSeconds: Double, base: Float, fastRate: Float) -> Double {
        guard base > 0, fastRate > base else { return 0 }
        return mediaSeconds / Double(base) - mediaSeconds / Double(fastRate)
    }

    /// Per-feed override (`true`/`false`) wins; `nil` = global.
    public static func isEnabled(feedOverride: Bool?, global: Bool) -> Bool {
        feedOverride ?? global
    }
}

/// Pipeline stage: measures each block and reports skip-state transitions.
/// `onChange` is called on the audio thread — hop to the main actor before touching the player.
public final class SilenceAnalysisStage: AudioBlockProcessor {
    private let lock = NSLock()
    private var detector: SilenceDetector
    private var _enabled = false
    private var _skippedMediaSeconds: Double = 0
    public var onChange: ((Bool) -> Void)?

    public init(detector: SilenceDetector = SilenceDetector()) {
        self.detector = detector
    }

    /// Swap detector thresholds (level change). Resets state; reports the end of an active skip.
    public func configure(_ newDetector: SilenceDetector) {
        lock.lock()
        let same = detector.thresholdDB == newDetector.thresholdDB
            && detector.releaseDB == newDetector.releaseDB
            && detector.minimumSilence == newDetector.minimumSilence
        let wasSkipping = detector.isSkipping
        if !same { detector = newDetector }
        lock.unlock()
        if !same, wasSkipping { onChange?(false) }
    }

    public var isEnabled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _enabled }
        set {
            lock.lock()
            let changed = _enabled != newValue
            _enabled = newValue
            let wasSkipping = detector.isSkipping
            if !newValue { detector.reset() }
            lock.unlock()
            if changed, !newValue, wasSkipping { onChange?(false) }
        }
    }

    /// Media seconds analysed while skipping (for time-saved stats).
    public var skippedMediaSeconds: Double {
        lock.lock(); defer { lock.unlock() }; return _skippedMediaSeconds
    }

    public func process(_ block: inout AudioBlock) {
        lock.lock()
        guard _enabled else { lock.unlock(); return }
        let level = AudioLevel.rmsDB(block)
        let changed = detector.feed(levelDB: level, duration: block.duration)
        let skipping = detector.isSkipping
        if skipping { _skippedMediaSeconds += block.duration }
        lock.unlock()
        if changed { onChange?(skipping) }
    }

    public func reset() {
        lock.lock()
        let wasSkipping = detector.isSkipping
        detector.reset()
        lock.unlock()
        if wasSkipping { onChange?(false) }
    }
}
