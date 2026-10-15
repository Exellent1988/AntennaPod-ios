import PodcastCore
import XCTest
@testable import AntennaPod

/// Sleep timer parity with Android AntennaPod: remembered last value, extend, shake reset,
/// auto-enable window, and the new global settings in UserDefaults and the JSON backup.
@MainActor
final class SleepTimerParityTests: XCTestCase {
    private var settings: AppSettings!
    private var original: AppSettingsBackupSnapshot!
    private var playback: PlaybackService!

    override func setUp() async throws {
        settings = AppSettings()
        original = settings.backupSnapshot()
        playback = PlaybackService()
        playback.settings = settings
    }

    override func tearDown() async throws {
        playback.disableSleepTimer()
        settings.applyBackupSnapshot(original)
        SettingsLeakObserver.restoreToTestStart()
    }

    func testStartingAClockTimerRemembersMinutesButAutoAndExtendDoNot() {
        playback.setSleepTimer(minutes: 25)
        XCTAssertEqual(settings.lastSleepTimerMinutes, 25)
        XCTAssertEqual(playback.sleepTimerRemainingSeconds, 25 * 60)
        playback.setSleepTimer(minutes: 7, remember: false)
        XCTAssertEqual(settings.lastSleepTimerMinutes, 25)
    }

    func testExtendAddsMinutesAndShakeResetRestoresInitialLength() {
        playback.setSleepTimer(minutes: 10)
        playback.extendSleepTimer(byMinutes: 30)
        XCTAssertEqual(playback.sleepTimerRemainingSeconds, 40 * 60)
        playback.resetSleepTimerToInitial()
        XCTAssertEqual(playback.sleepTimerRemainingSeconds, 10 * 60, "Android reset() goes back to initialWaitingTime")
        XCTAssertTrue(playback.isSleepTimerActive)
    }

    func testExtendOnEndOfEpisodeStartsClockTimer() {
        playback.setSleepTimerEndOfEpisode()
        playback.extendSleepTimer(byMinutes: 5)
        XCTAssertEqual(playback.sleepTimerMode, .clock(minutes: 5))
    }

    func testAutoEnableInsideWindowStartsLastTimer() {
        settings.sleepTimerAutoEnable = true
        settings.sleepTimerAutoEnableFromHour = 22
        settings.sleepTimerAutoEnableToHour = 6
        settings.lastSleepTimerMinutes = 20
        playback.autoEnableSleepTimerIfNeeded(now: date(hour: 23))
        XCTAssertTrue(playback.isSleepTimerActive)
        XCTAssertTrue(playback.sleepTimerWasAutoEnabled)
        XCTAssertEqual(playback.sleepTimerRemainingSeconds, 20 * 60)
        playback.disableSleepTimer()   // Undo
        XCTAssertFalse(playback.sleepTimerWasAutoEnabled)
    }

    func testAutoEnableOutsideWindowOrOffOrAlreadyRunningDoesNothing() {
        settings.sleepTimerAutoEnable = true
        settings.sleepTimerAutoEnableFromHour = 22
        settings.sleepTimerAutoEnableToHour = 6
        playback.autoEnableSleepTimerIfNeeded(now: date(hour: 12))
        XCTAssertFalse(playback.isSleepTimerActive)

        settings.sleepTimerAutoEnable = false
        playback.autoEnableSleepTimerIfNeeded(now: date(hour: 23))
        XCTAssertFalse(playback.isSleepTimerActive)

        settings.sleepTimerAutoEnable = true
        playback.setSleepTimer(minutes: 45)
        playback.autoEnableSleepTimerIfNeeded(now: date(hour: 23))
        XCTAssertEqual(playback.sleepTimerRemainingSeconds, 45 * 60, "A running timer is not replaced")
        XCTAssertFalse(playback.sleepTimerWasAutoEnabled)
    }

    func testDefaultsMatchAndroid() throws {
        var snap = settings.backupSnapshot()
        snap.sleepTimerVibrate = nil
        snap.sleepTimerShakeToReset = nil
        snap.sleepTimerAutoEnable = nil
        snap.sleepTimerAutoEnableFromHour = nil
        snap.sleepTimerAutoEnableToHour = nil
        snap.lastSleepTimerMinutes = nil
        settings.applyBackupSnapshot(snap)   // an older backup without the new fields
        XCTAssertFalse(settings.sleepTimerVibrate)
        XCTAssertTrue(settings.sleepTimerShakeToReset)
        XCTAssertFalse(settings.sleepTimerAutoEnable)
        XCTAssertEqual(settings.sleepTimerAutoEnableFromHour, 22)
        XCTAssertEqual(settings.sleepTimerAutoEnableToHour, 6)
        XCTAssertEqual(settings.lastSleepTimerMinutes, 15)
    }

    func testNewSettingsSurviveBackupAndUserDefaults() throws {
        settings.sleepTimerVibrate = true
        settings.sleepTimerShakeToReset = false
        settings.sleepTimerAutoEnable = true
        settings.sleepTimerAutoEnableFromHour = 21
        settings.sleepTimerAutoEnableToHour = 7
        settings.lastSleepTimerMinutes = 33
        let reloaded = AppSettings()
        XCTAssertTrue(reloaded.sleepTimerVibrate)
        XCTAssertFalse(reloaded.sleepTimerShakeToReset)
        XCTAssertEqual(reloaded.sleepTimerAutoEnableFromHour, 21)
        XCTAssertEqual(reloaded.lastSleepTimerMinutes, 33)

        let snap = try JSONDecoder().decode(AppSettingsBackupSnapshot.self,
                                            from: JSONEncoder().encode(settings.backupSnapshot()))
        settings.applyBackupSnapshot(original)
        SettingsLeakObserver.restoreToTestStart()
        settings.applyBackupSnapshot(snap)
        XCTAssertTrue(settings.sleepTimerVibrate)
        XCTAssertFalse(settings.sleepTimerShakeToReset)
        XCTAssertTrue(settings.sleepTimerAutoEnable)
        XCTAssertEqual(settings.sleepTimerAutoEnableFromHour, 21)
        XCTAssertEqual(settings.sleepTimerAutoEnableToHour, 7)
        XCTAssertEqual(settings.lastSleepTimerMinutes, 33)
    }

    func testBackupClampsHoursAndMinutes() {
        var snap = settings.backupSnapshot()
        snap.sleepTimerAutoEnableFromHour = 30
        snap.sleepTimerAutoEnableToHour = -2
        snap.lastSleepTimerMinutes = 999
        settings.applyBackupSnapshot(snap)
        XCTAssertEqual(settings.sleepTimerAutoEnableFromHour, 23)
        XCTAssertEqual(settings.sleepTimerAutoEnableToHour, 0)
        XCTAssertEqual(settings.lastSleepTimerMinutes, PlaybackService.customSleepTimerMinutesRange.upperBound)
    }

    private func date(hour: Int) -> Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = hour
        c.minute = 30
        return Calendar.current.date(from: c)!
    }
}
