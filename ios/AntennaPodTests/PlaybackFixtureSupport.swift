import AVFoundation
import XCTest
@testable import AntennaPod

/// Shared fixture for real-`AVPlayer` playback tests: a real `PodcastStore` + `PlaybackService`
/// (store maps saved and restored), three generated 3 s CAF files (tone + silence) in a temp
/// folder played from file URLs, queued in order. No network.
@MainActor
class PlaybackFixtureTestCase: XCTestCase {
    var settings: AppSettings!
    var settingsSnapshot: AppSettingsBackupSnapshot!
    var store: PodcastStore!
    var playback: PlaybackService!
    var savedQueue: [PodcastEpisode] = []
    var savedStates: [String: EpisodePlaybackState] = [:]
    var fixtureDir: URL!
    var episodes: [PodcastEpisode] = []
    /// Players dropped by kill/relaunch simulations. Kept alive until tearDown and stopped there,
    /// so no AVPlayer time observer or Task outlives the test into a deallocated service.
    var retiredPlaybacks: [PlaybackService] = []

    /// Fixture length; long enough for the 0.5 s time observer to tick a few times.
    static let fixtureSeconds = 3.0
    private var rawSettings: [String: NSObject] = [:]

    override func setUp() async throws {
        // No audible output from fixture playback (also set by the principal class).
        PlaybackService.silentOutputForTests = true
        rawSettings = SettingsLeakObserver.snapshot()
        settings = AppSettings()
        settingsSnapshot = settings.backupSnapshot()
        settings.continuousPlaybackMode = .queue
        settings.skipIntroSeconds = 0
        settings.skipOutroSeconds = 0
        settings.sleepTimerAutoEnable = false
        settings.resetPositionWhenMarkedPlayed = true
        settings.playbackSourcePreference = .automatic
        // Older finish-path tests expect a skip to mark played; KeepSkippedEpisodesTests covers the default.
        settings.keepSkippedEpisodes = false

        store = PodcastStore()
        savedQueue = store.queue
        savedStates = store.playbackStates
        store.settings = settings
        playback = PlaybackService()
        playback.settings = settings
        playback.store = store
        store.playback = playback

        fixtureDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("e2e-fixtures-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureDir, withIntermediateDirectories: true)
        let run = UUID().uuidString.prefix(8)
        episodes = try (1...3).map { n in
            let url = fixtureDir.appendingPathComponent("ep\(n).caf")
            try Self.writeFixture(to: url, seconds: Self.fixtureSeconds, frequency: 300 + Double(n) * 110)
            return PodcastEpisode(id: "e2e-\(run)-\(n)", title: "E2E \(n)", downloadUrl: url.absoluteString,
                                  mimeType: "audio/x-caf", durationSeconds: Self.fixtureSeconds)
        }
        store.queue = episodes
    }

    override func tearDown() async throws {
        for old in retiredPlaybacks {
            old.disableSleepTimer()
            old.stop()
        }
        retiredPlaybacks.removeAll()
        playback.disableSleepTimer()
        playback.stop()
        store.queue = savedQueue
        store.playbackStates = savedStates
        settings.applyBackupSnapshot(settingsSnapshot)
        SettingsLeakObserver.restoreToTestStart()
        // A backup restore writes defaults for keys that were never set; put the raw values back
        // (and remove keys that did not exist) so the test leaves persisted settings untouched.
        SettingsLeakObserver.restore(rawSettings, over: SettingsLeakObserver.snapshot())
        try? FileManager.default.removeItem(at: fixtureDir)
    }

    // MARK: Helpers

    func assertFinished(_ episode: PodcastEpisode, file: StaticString = #filePath, line: UInt = #line) {
        let state = store.playbackState(for: episode.id)
        XCTAssertTrue(state.isPlayed, "\(episode.title) marked played", file: file, line: line)
        XCTAssertEqual(state.positionSeconds, 0, "Reset position when marked played", file: file, line: line)
        XCTAssertEqual(state.durationSeconds, Self.fixtureSeconds, accuracy: 0.2, file: file, line: line)
    }

    func waitFor(_ what: String, timeout: TimeInterval, _ condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for \(what) (episode \(playback.currentEpisode?.title ?? "none"), "
                        + "position \(playback.positionSeconds), playing \(playback.isPlaying))")
                throw CancellationError()
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    /// Mono 44.1 kHz CAF: tone for the first half, silence for the rest.
    static func writeFixture(to url: URL, seconds: Double, frequency: Double) throws {
        let rate = 44_100.0
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let frames = AVAudioFrameCount(seconds * rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let samples = buffer.floatChannelData![0]
        for i in 0..<Int(frames) {
            samples[i] = Double(i) < Double(frames) / 2 ? Float(0.2 * sin(2 * .pi * frequency * Double(i) / rate)) : 0
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
