import AVFoundation
import PodcastCore
import XCTest
@testable import AntennaPod

/// Android interruption parity, driven with real local playback (`PlaybackFixtureTestCase`)
/// and synthetic route / interruption events (no hardware in the simulator).
@MainActor
final class PlaybackInterruptionsTests: PlaybackFixtureTestCase {
    private let headphones = ["Headphones"]
    private let bluetooth = ["BluetoothA2DPOutput"]

    // MARK: Reconnect

    func testReconnectDefaultsAndBackup() throws {
        var old = settings.backupSnapshot()
        old.resumeOnHeadphonesReconnect = nil
        old.resumeOnBluetoothReconnect = nil
        settings.applyBackupSnapshot(old)   // older backup without the keys
        XCTAssertTrue(settings.resumeOnHeadphonesReconnect, "Android default on")
        XCTAssertFalse(settings.resumeOnBluetoothReconnect, "Android default off")
        settings.resumeOnHeadphonesReconnect = false
        settings.resumeOnBluetoothReconnect = true
        let data = try JSONEncoder().encode(settings.backupSnapshot())
        let snap = try JSONDecoder().decode(AppSettingsBackupSnapshot.self, from: data)
        settings.resumeOnHeadphonesReconnect = true
        settings.resumeOnBluetoothReconnect = false
        settings.applyBackupSnapshot(snap)
        XCTAssertFalse(settings.resumeOnHeadphonesReconnect)
        XCTAssertTrue(settings.resumeOnBluetoothReconnect)
        XCTAssertFalse(AppSettings().resumeOnHeadphonesReconnect, "Persists in UserDefaults")
    }

    func testUnplugPausesAndHeadphonesReconnectResumes() async throws {
        let ep = longEpisode()
        XCTAssertTrue(playback.play(episode: ep))
        try await waitFor("playing", timeout: 8) { self.playback.isPlaying && self.playback.positionSeconds > 0.5 }
        playback.handleRouteChange(reason: .oldDeviceUnavailable, currentOutputPorts: ["Speaker"])
        XCTAssertFalse(playback.isPlaying)
        XCTAssertNotNil(playback.pausedByUnplugAt)
        playback.handleRouteChange(reason: .newDeviceAvailable, currentOutputPorts: headphones)
        XCTAssertTrue(playback.isPlaying, "Headphones reconnect (default on) resumes")
        XCTAssertNil(playback.pausedByUnplugAt)
    }

    func testBluetoothReconnectFollowsItsOwnSetting() async throws {
        XCTAssertTrue(playback.play(episode: longEpisode()))
        try await waitFor("playing", timeout: 8) { self.playback.isPlaying && self.playback.positionSeconds > 0.5 }
        playback.handleRouteChange(reason: .oldDeviceUnavailable, currentOutputPorts: ["Speaker"])
        playback.handleRouteChange(reason: .newDeviceAvailable, currentOutputPorts: bluetooth)
        XCTAssertFalse(playback.isPlaying, "Bluetooth reconnect is off by default")
        settings.resumeOnBluetoothReconnect = true
        playback.handleRouteChange(reason: .newDeviceAvailable, currentOutputPorts: bluetooth)
        XCTAssertTrue(playback.isPlaying)
    }

    func testUserPauseOrLateReconnectDoesNotResume() async throws {
        XCTAssertTrue(playback.play(episode: longEpisode()))
        try await waitFor("playing", timeout: 8) { self.playback.isPlaying && self.playback.positionSeconds > 0.5 }
        // Unplug, then the user presses play and pause again: their pause wins.
        playback.handleRouteChange(reason: .oldDeviceUnavailable, currentOutputPorts: ["Speaker"])
        playback.togglePlayPause()
        playback.togglePlayPause()
        XCTAssertFalse(playback.isPlaying)
        playback.handleRouteChange(reason: .newDeviceAvailable, currentOutputPorts: headphones)
        XCTAssertFalse(playback.isPlaying)
        // Unplug pause, reconnect after the window.
        playback.togglePlayPause()
        XCTAssertTrue(playback.isPlaying)
        let t0 = Date()
        playback.handleRouteChange(reason: .oldDeviceUnavailable, currentOutputPorts: ["Speaker"], now: t0)
        playback.handleRouteChange(reason: .newDeviceAvailable, currentOutputPorts: headphones,
                                   now: t0.addingTimeInterval(ReconnectResumePolicy.resumeWindowSeconds + 5))
        XCTAssertFalse(playback.isPlaying)
    }

    func testUnplugWhilePausedDoesNotArmResume() async throws {
        XCTAssertTrue(playback.play(episode: longEpisode()))
        try await waitFor("playing", timeout: 8) { self.playback.isPlaying }
        playback.togglePlayPause()
        playback.handleRouteChange(reason: .oldDeviceUnavailable, currentOutputPorts: ["Speaker"])
        XCTAssertNil(playback.pausedByUnplugAt)
        playback.handleRouteChange(reason: .newDeviceAvailable, currentOutputPorts: headphones)
        XCTAssertFalse(playback.isPlaying)
    }

    // MARK: Helpers

    /// 30 s fixture so nothing ends while a test pauses and resumes.
    func longEpisode() -> PodcastEpisode {
        let url = fixtureDir.appendingPathComponent("long.caf")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? Self.writeFixture(to: url, seconds: 30, frequency: 440)
        }
        let ep = PodcastEpisode(id: "e2e-long-\(UUID().uuidString.prefix(6))", title: "Long", downloadUrl: url.absoluteString,
                                mimeType: "audio/x-caf", durationSeconds: 30)
        store.queue.insert(ep, at: 0)
        return ep
    }
}

@MainActor
final class PauseForInterruptionsTests: PlaybackFixtureTestCase {
    func testDefaultBackupAndSessionMode() throws {
        var old = settings.backupSnapshot()
        old.pauseForInterruptions = nil
        settings.applyBackupSnapshot(old)
        XCTAssertTrue(settings.pauseForInterruptions, "Android prefPauseForFocusLoss default on")
        XCTAssertEqual(playback.preferredAudioSessionMode(), .spokenAudio)
        settings.pauseForInterruptions = false
        XCTAssertEqual(playback.preferredAudioSessionMode(), .default, "Off → prompts duck us")
        let snap = try JSONDecoder().decode(AppSettingsBackupSnapshot.self, from: JSONEncoder().encode(settings.backupSnapshot()))
        settings.pauseForInterruptions = true
        settings.applyBackupSnapshot(snap)
        XCTAssertFalse(settings.pauseForInterruptions)
    }

    func testInterruptionPausesAndResumesWhenSystemAllows() async throws {
        XCTAssertTrue(playback.play(episode: episodes[0]))
        try await waitFor("playing", timeout: 8) { self.playback.isPlaying }
        playback.handleInterruption(.began, systemShouldResume: false)
        XCTAssertFalse(playback.isPlaying)
        playback.handleInterruption(.ended, systemShouldResume: true)
        XCTAssertTrue(playback.isPlaying)
    }

    func testNoResumeWithoutShouldResumeOrAfterUserAction() async throws {
        XCTAssertTrue(playback.play(episode: episodes[0]))
        try await waitFor("playing", timeout: 8) { self.playback.isPlaying }
        playback.handleInterruption(.began, systemShouldResume: false)
        playback.handleInterruption(.ended, systemShouldResume: false)
        XCTAssertFalse(playback.isPlaying)
        playback.togglePlayPause()
        XCTAssertTrue(playback.isPlaying)
        playback.handleInterruption(.began, systemShouldResume: false)
        playback.togglePlayPause()   // user presses play during the interruption…
        playback.togglePlayPause()   // …and pause again
        playback.handleInterruption(.ended, systemShouldResume: true)
        XCTAssertFalse(playback.isPlaying, "The user's pause wins")
    }
}
