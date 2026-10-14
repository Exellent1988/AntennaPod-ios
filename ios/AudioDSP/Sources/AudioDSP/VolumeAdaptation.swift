import Foundation

/// Per-podcast volume adaptation (Android `VolumeAdaptionSetting`): fixed gain applied in the
/// playback pipeline. Reductions match Android's volume factors (0.5 / 0.2); boosts are
/// +6 / +12 / +18 dB with the pipeline soft limiter (Android uses `LoudnessEnhancer`).
public enum VolumeAdaptationMode: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case off
    case lightReduction
    case heavyReduction
    case lightBoost
    case mediumBoost
    case heavyBoost

    public var id: String { rawValue }

    /// Linear gain factor for this mode.
    public var gainFactor: Float {
        switch self {
        case .off: return 1
        case .lightReduction: return 0.5
        case .heavyReduction: return 0.2
        case .lightBoost: return AudioLevel.linear(fromDB: 6)
        case .mediumBoost: return AudioLevel.linear(fromDB: 12)
        case .heavyBoost: return AudioLevel.linear(fromDB: 18)
        }
    }

    /// Per-feed override wins; `nil` = use global.
    public static func resolved(feed: VolumeAdaptationMode?, global: VolumeAdaptationMode) -> VolumeAdaptationMode {
        feed ?? global
    }

    /// Static pipeline gain: Volume boost percent (100 = unity) × reduction factor.
    /// Boost modes are handled by `LoudnessEnhancerStage` (adaptive makeup gain) instead.
    public static func pipelineGain(boostPercent: Int, mode: VolumeAdaptationMode) -> Float {
        Float(max(0, boostPercent)) / 100 * mode.staticGainFactor
    }
}
