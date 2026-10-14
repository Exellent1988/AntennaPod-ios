import AudioDSP
import Foundation

/// Owns sample storage for a test block.
final class TestBuffer {
    var storage: [[Float]]
    let sampleRate: Double
    init(channels: Int, frames: Int, sampleRate: Double = 44_100, fill: (Int) -> Float) {
        self.sampleRate = sampleRate
        storage = (0..<channels).map { _ in (0..<frames).map(fill) }
    }
    func withBlock<R>(_ body: (inout AudioBlock) -> R) -> R {
        let ptrs = storage.map { arr -> UnsafeMutableBufferPointer<Float> in
            let p = UnsafeMutableBufferPointer<Float>.allocate(capacity: arr.count)
            _ = p.initialize(from: arr)
            return p
        }
        defer { ptrs.forEach { $0.deallocate() } }
        var block = AudioBlock(channels: ptrs, frameCount: storage[0].count, sampleRate: sampleRate)
        let r = body(&block)
        storage = ptrs.map { Array($0) }
        return r
    }
    static func sine(amplitude: Float, frames: Int = 4410, channels: Int = 2) -> TestBuffer {
        TestBuffer(channels: channels, frames: frames) { i in amplitude * Float(sin(2 * Double.pi * 440 * Double(i) / 44_100)) }
    }
}
