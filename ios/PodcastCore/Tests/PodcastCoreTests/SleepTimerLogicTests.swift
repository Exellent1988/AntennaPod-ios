import XCTest
@testable import PodcastCore

final class SleepTimerLogicTests: XCTestCase {
    func testDaytimeWindow() {
        XCTAssertTrue(SleepTimerLogic.isInAutoEnableWindow(fromHour: 9, toHour: 17, hour: 9))
        XCTAssertTrue(SleepTimerLogic.isInAutoEnableWindow(fromHour: 9, toHour: 17, hour: 16))
        XCTAssertFalse(SleepTimerLogic.isInAutoEnableWindow(fromHour: 9, toHour: 17, hour: 17))
        XCTAssertFalse(SleepTimerLogic.isInAutoEnableWindow(fromHour: 9, toHour: 17, hour: 3))
    }

    func testOvernightWindow() {
        for hour in [22, 23, 0, 3, 5] {
            XCTAssertTrue(SleepTimerLogic.isInAutoEnableWindow(fromHour: 22, toHour: 6, hour: hour), "\(hour)")
        }
        for hour in [6, 12, 21] {
            XCTAssertFalse(SleepTimerLogic.isInAutoEnableWindow(fromHour: 22, toHour: 6, hour: hour), "\(hour)")
        }
    }

    func testSameHourMeansAllDayAndHoursWrap() {
        XCTAssertTrue(SleepTimerLogic.isInAutoEnableWindow(fromHour: 8, toHour: 8, hour: 20))
        XCTAssertTrue(SleepTimerLogic.isInAutoEnableWindow(fromHour: 22, toHour: 6, hour: 24))
        XCTAssertEqual(SleepTimerLogic.autoEnableDurationHours(fromHour: 22, toHour: 6), 8)
        XCTAssertEqual(SleepTimerLogic.autoEnableDurationHours(fromHour: 9, toHour: 17), 8)
        XCTAssertEqual(SleepTimerLogic.autoEnableDurationHours(fromHour: 5, toHour: 5), 24)
    }

    func testShouldAutoEnable() {
        XCTAssertTrue(SleepTimerLogic.shouldAutoEnable(enabled: true, timerActive: false, fromHour: 22, toHour: 6, hour: 23))
        XCTAssertFalse(SleepTimerLogic.shouldAutoEnable(enabled: false, timerActive: false, fromHour: 22, toHour: 6, hour: 23))
        XCTAssertFalse(SleepTimerLogic.shouldAutoEnable(enabled: true, timerActive: true, fromHour: 22, toHour: 6, hour: 23))
        XCTAssertFalse(SleepTimerLogic.shouldAutoEnable(enabled: true, timerActive: false, fromHour: 22, toHour: 6, hour: 12))
    }

    func testRemaining() {
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(SleepTimerLogic.remainingSeconds(endDate: now.addingTimeInterval(90), pausedRemaining: 5, now: now), 90)
        XCTAssertEqual(SleepTimerLogic.remainingSeconds(endDate: now.addingTimeInterval(-3), pausedRemaining: nil, now: now), 0)
        XCTAssertEqual(SleepTimerLogic.remainingSeconds(endDate: nil, pausedRemaining: 42, now: now), 42)
        XCTAssertNil(SleepTimerLogic.remainingSeconds(endDate: nil, pausedRemaining: nil, now: now))
    }

    func testWarningWindow() {
        XCTAssertFalse(SleepTimerLogic.isInWarningWindow(remaining: 10))
        XCTAssertTrue(SleepTimerLogic.isInWarningWindow(remaining: 9.9))
        XCTAssertTrue(SleepTimerLogic.isInWarningWindow(remaining: 0.1))
        XCTAssertFalse(SleepTimerLogic.isInWarningWindow(remaining: 0))
    }

    func testFadeCurveMatchesAndroidStepsAndIsMonotonic() {
        XCTAssertEqual(SleepTimerLogic.fadeVolume(remaining: 60), 1)
        XCTAssertEqual(SleepTimerLogic.fadeVolume(remaining: 10), 1)
        for (second, step) in SleepTimerLogic.androidFadeSteps.enumerated() {
            XCTAssertEqual(SleepTimerLogic.fadeVolume(remaining: Double(second)), step, accuracy: 0.0001)
        }
        XCTAssertEqual(SleepTimerLogic.fadeVolume(remaining: 0), 0.1, accuracy: 0.0001)
        var last: Float = 0
        for tenth in 0...100 {
            let v = SleepTimerLogic.fadeVolume(remaining: Double(tenth) / 10)
            XCTAssertGreaterThanOrEqual(v, last - 0.0001)
            last = v
        }
        XCTAssertEqual(SleepTimerLogic.fadeVolume(remaining: .nan), 1)
    }

    func testShake() {
        XCTAssertFalse(SleepTimerLogic.isShake(x: 0, y: 0, z: -1), "Resting phone = 1 g")
        XCTAssertFalse(SleepTimerLogic.isShake(x: 1.5, y: 1, z: 1))
        XCTAssertTrue(SleepTimerLogic.isShake(x: 2, y: 1, z: 1))
    }
}
