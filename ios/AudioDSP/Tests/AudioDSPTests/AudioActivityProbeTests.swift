import AudioDSP
import XCTest

final class AudioActivityProbeTests: XCTestCase {
    func testInactiveUntilAudioFlowsThenExpires() {
        let probe = AudioActivityProbe()
        XCTAssertFalse(probe.isActive())
        let buffer = TestBuffer.sine(amplitude: 0.5, frames: 64)
        let before = buffer.storage
        buffer.withBlock { probe.process(&$0) }
        XCTAssertEqual(buffer.storage, before, "Probe never changes samples")
        XCTAssertTrue(probe.isActive())
        XCTAssertFalse(probe.isActive(within: 1, now: ProcessInfo.processInfo.systemUptime + 5))
    }

    func testFadeStageAttenuatesAfterRamp() {
        let fade = GainStage()
        fade.gain = 0.1
        let buffer = TestBuffer(channels: 1, frames: 256) { _ in 1 }
        buffer.withBlock { fade.process(&$0) }   // ramp block
        buffer.storage = [Array(repeating: 1, count: 256)]
        buffer.withBlock { fade.process(&$0) }
        XCTAssertEqual(buffer.storage[0].last ?? 0, 0.1, accuracy: 0.001)
    }
}
