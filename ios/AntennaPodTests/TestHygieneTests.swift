import AudioDSP
import XCTest
@testable import AntennaPod

/// Records the loudest block the tap delivered (audio thread → lock).
private final class PeakProbe: AudioBlockProcessor {
    private let lock = NSLock()
    private var peak: Double = AudioLevel.floorDB
    var peakDB: Double { lock.lock(); defer { lock.unlock() }; return peak }
    func process(_ block: inout AudioBlock) {
        let db = AudioLevel.rmsDB(block)
        lock.lock(); peak = max(peak, db); lock.unlock()
    }
    func reset() {}
}

/// Test runs must be silent (muted output stage) while the tap still sees the real samples.
@MainActor
final class TestHygieneTests: PlaybackFixtureTestCase {
    func testFixturePlaybackIsMutedButTapSeesSignal() async throws {
        XCTAssertTrue(playback.play(episode: episodes[0]))
        try await waitFor("playing", timeout: 5) { self.playback.isPlaying }
        XCTAssertEqual(playback.isOutputMutedForTests, true, "fixture playback must be muted")
        let pipeline = try XCTUnwrap(playback.audioPipeline, "tap pipeline installed for local file")
        let probe = PeakProbe()
        pipeline.chain.append(probe)
        try await waitFor("tap delivers signal", timeout: 4) { probe.peakDB > -40 }
        XCTAssertTrue(pipeline.activity.isActive(within: 2))
    }
}
