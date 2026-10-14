import Foundation

/// Settings for the RMS-based makeup gain (closer to Android `LoudnessEnhancer` than a static boost).
public struct LoudnessProfile: Hashable, Sendable {
    /// Level the stage tries to bring speech up to (dBFS RMS).
    public var targetDB: Double
    /// Upper bound of the makeup gain (dB).
    public var maxGainDB: Double
    /// Blocks quieter than this are treated as pauses: gain is held, noise is not pumped up.
    public var gateDB: Double
    /// Time constant when gain must drop (loud passage): fast, avoids overshoot.
    public var attackSeconds: Double
    /// Time constant when gain may rise (quiet passage): slow, avoids pumping.
    public var releaseSeconds: Double

    public init(targetDB: Double, maxGainDB: Double, gateDB: Double = -50,
                attackSeconds: Double = 0.05, releaseSeconds: Double = 1.0) {
        self.targetDB = targetDB
        self.maxGainDB = maxGainDB
        self.gateDB = gateDB
        self.attackSeconds = attackSeconds
        self.releaseSeconds = releaseSeconds
    }
}

public extension VolumeAdaptationMode {
    /// Makeup-gain profile for boost modes; `nil` for off / reductions (static gain).
    var loudnessProfile: LoudnessProfile? {
        switch self {
        case .off, .lightReduction, .heavyReduction: return nil
        case .lightBoost: return LoudnessProfile(targetDB: -20, maxGainDB: 6)
        case .mediumBoost: return LoudnessProfile(targetDB: -18, maxGainDB: 12)
        case .heavyBoost: return LoudnessProfile(targetDB: -16, maxGainDB: 18)
        }
    }

    /// Static part of the gain: the reduction factor, or 1 when the loudness stage handles a boost.
    var staticGainFactor: Float { loudnessProfile == nil ? gainFactor : 1 }
}

/// Pure gain computer for the loudness stage (one step per analysed block).
public struct LoudnessGainComputer: Sendable {
    public var profile: LoudnessProfile
    public private(set) var gainDB: Double = 0

    public init(profile: LoudnessProfile) { self.profile = profile }

    /// Gain the stage wants for a block at `levelDB` (before smoothing).
    public func desiredGainDB(levelDB: Double) -> Double {
        guard levelDB > profile.gateDB else { return gainDB } // hold through pauses
        return min(max(profile.targetDB - levelDB, 0), profile.maxGainDB)
    }

    /// Advance by one block; returns the new smoothed gain in dB.
    @discardableResult
    public mutating func step(levelDB: Double, duration: Double) -> Double {
        let desired = desiredGainDB(levelDB: levelDB)
        let tau = desired < gainDB ? profile.attackSeconds : profile.releaseSeconds
        let alpha = tau > 0 ? 1 - exp(-max(0, duration) / tau) : 1
        gainDB += (desired - gainDB) * alpha
        return gainDB
    }

    /// Glide back toward 0 dB (stage disabled).
    public mutating func relax(duration: Double) {
        let alpha = 1 - exp(-max(0, duration) / profile.attackSeconds)
        gainDB -= gainDB * alpha
        if abs(gainDB) < 0.01 { gainDB = 0 }
    }

    public mutating func reset() { gainDB = 0 }
}

/// Pipeline stage: RMS makeup gain with attack/release, per-sample ramp, and soft limiter.
public final class LoudnessEnhancerStage: AudioBlockProcessor {
    private let lock = NSLock()
    private var computer = LoudnessGainComputer(profile: LoudnessProfile(targetDB: -20, maxGainDB: 0))
    private var enabled = false

    public init() {}

    /// `nil` disables the stage (gain glides back to unity).
    public func configure(_ profile: LoudnessProfile?) {
        lock.lock(); defer { lock.unlock() }
        if let profile {
            computer.profile = profile
            enabled = true
        } else {
            enabled = false
        }
    }

    public var currentGainDB: Double {
        lock.lock(); defer { lock.unlock() }; return computer.gainDB
    }

    public func process(_ block: inout AudioBlock) {
        lock.lock()
        let before = computer.gainDB
        if enabled {
            computer.step(levelDB: AudioLevel.rmsDB(block), duration: block.duration)
        } else {
            computer.relax(duration: block.duration)
        }
        let after = computer.gainDB
        lock.unlock()
        if before == 0, after == 0 { return }
        GainRamp.apply(&block, from: AudioLevel.linear(fromDB: before), to: AudioLevel.linear(fromDB: after), limit: true)
    }

    public func reset() {
        lock.lock(); computer.reset(); lock.unlock()
    }
}

/// Linear per-sample gain ramp across a block (click-free gain changes).
public enum GainRamp {
    public static func apply(_ block: inout AudioBlock, from: Float, to: Float, limit: Bool) {
        let n = block.frameCount
        guard n > 0 else { return }
        let step = (to - from) / Float(n)
        for ch in block.channels {
            let count = min(n, ch.count)
            var g = from
            for i in 0..<count {
                g += step
                var s = ch[i] * g
                if limit { s = GainStage.softClip(s) }
                ch[i] = s
            }
        }
    }
}
