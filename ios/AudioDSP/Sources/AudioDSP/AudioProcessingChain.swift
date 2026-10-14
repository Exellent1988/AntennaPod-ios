import Foundation

/// One block of non-interleaved Float32 PCM, as delivered by `MTAudioProcessingTap`
/// (one pointer per channel, `frameCount` samples each).
public struct AudioBlock {
    public var channels: [UnsafeMutableBufferPointer<Float>]
    public var frameCount: Int
    public var sampleRate: Double

    public init(channels: [UnsafeMutableBufferPointer<Float>], frameCount: Int, sampleRate: Double) {
        self.channels = channels
        self.frameCount = frameCount
        self.sampleRate = sampleRate
    }

    /// Duration of this block in seconds (0 when the sample rate is unknown).
    public var duration: Double { sampleRate > 0 ? Double(frameCount) / sampleRate : 0 }
}

/// A stage in the playback audio pipeline. Called on the real-time audio thread:
/// no allocation, no locks held for long, no main-actor work.
public protocol AudioBlockProcessor: AnyObject {
    func process(_ block: inout AudioBlock)
    /// Called on seek / new item so stateful stages drop history.
    func reset()
}

public extension AudioBlockProcessor {
    func reset() {}
}

/// Ordered list of processors shared by every audio track of the current player item.
/// The app builds one chain per `AVPlayerItem`; stages are added by features
/// (volume adaptation, skip-silence analysis, …) so they all share one tap.
public final class AudioProcessingChain {
    private let lock = NSLock()
    private var stages: [AudioBlockProcessor]

    public init(stages: [AudioBlockProcessor] = []) {
        self.stages = stages
    }

    public func append(_ stage: AudioBlockProcessor) {
        lock.lock(); defer { lock.unlock() }
        stages.append(stage)
    }

    public var stageCount: Int {
        lock.lock(); defer { lock.unlock() }
        return stages.count
    }

    public func process(_ block: inout AudioBlock) {
        lock.lock()
        let snapshot = stages
        lock.unlock()
        for stage in snapshot {
            stage.process(&block)
        }
    }

    public func reset() {
        lock.lock()
        let snapshot = stages
        lock.unlock()
        snapshot.forEach { $0.reset() }
    }
}

/// Level helpers (dBFS) shared by stages.
public enum AudioLevel {
    /// Lowest level reported; digital silence maps here instead of -inf.
    public static let floorDB: Double = -120

    /// RMS over all channels of the block, in dBFS (full scale sine ≈ -3 dBFS).
    public static func rmsDB(_ block: AudioBlock) -> Double {
        var sum: Double = 0
        var count = 0
        for ch in block.channels {
            let n = min(block.frameCount, ch.count)
            for i in 0..<n {
                let s = Double(ch[i])
                sum += s * s
            }
            count += n
        }
        guard count > 0, sum > 0 else { return floorDB }
        return max(floorDB, 10 * log10(sum / Double(count)))
    }

    public static func linear(fromDB db: Double) -> Float { Float(pow(10, db / 20)) }
}

/// Thread-safe linear gain with a soft limiter above unity so boosts do not hard-clip.
public final class GainStage: AudioBlockProcessor {
    private let lock = NSLock()
    private var _gain: Float = 1

    public init(gain: Float = 1) { _gain = gain }

    public var gain: Float {
        get { lock.lock(); defer { lock.unlock() }; return _gain }
        set { lock.lock(); _gain = max(0, newValue); lock.unlock() }
    }

    public func process(_ block: inout AudioBlock) {
        let g = gain
        if abs(g - 1) < 0.0001 { return }
        let limit = g > 1
        for ch in block.channels {
            let n = min(block.frameCount, ch.count)
            for i in 0..<n {
                var s = ch[i] * g
                if limit { s = GainStage.softClip(s) }
                ch[i] = s
            }
        }
    }

    /// Linear below 0.8, smooth tanh knee to ±1 above.
    @inline(__always)
    public static func softClip(_ x: Float) -> Float {
        let knee: Float = 0.8
        let a = abs(x)
        if a <= knee { return x }
        let over = (a - knee) / (1 - knee)
        let y = knee + (1 - knee) * Float(tanh(Double(over)))
        return x < 0 ? -y : y
    }
}
