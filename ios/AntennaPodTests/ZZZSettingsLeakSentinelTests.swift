import XCTest

/// Runs last (XCTest orders classes by name): fails when any earlier test leaked persisted settings.
final class ZZZSettingsLeakSentinelTests: XCTestCase {
    func testNoEarlierTestLeakedSettings() {
        XCTAssertEqual(SettingsLeakObserver.leaks, [], "Tests must save and restore every setting they change")
    }

    func testLeakDetectionSeesChangedAddedAndRemovedKeys() {
        let a: [String: NSObject] = ["settings.a": 1 as NSNumber, "settings.b": true as NSNumber]
        let b: [String: NSObject] = ["settings.a": 2 as NSNumber, "settings.c": "x" as NSString]
        XCTAssertEqual(SettingsLeakObserver.leakedKeys(before: a, after: b), ["settings.a", "settings.b", "settings.c"])
        XCTAssertEqual(SettingsLeakObserver.leakedKeys(before: a, after: a), [])
    }

    /// Simulates a test host killed mid-test: the journal from before the test brings the values back.
    func testJournalRestoresSettingsLeftByAKilledTest() throws {
        let key = "settings.keepSkippedEpisodes"
        let original = UserDefaults.standard.object(forKey: key)
        defer {
            if let original { UserDefaults.standard.set(original, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.set(true, forKey: key)
        var saved = SettingsLeakObserver.snapshot()
        saved["settings.zzKilledProbe"] = nil
        let data = try PropertyListSerialization.data(fromPropertyList: ["test": "killed", "settings": saved], format: .binary, options: 0)
        // What a killed KeepSkippedEpisodesTests.testOff… leaves behind.
        UserDefaults.standard.set(false, forKey: key)
        UserDefaults.standard.set(1, forKey: "settings.zzKilledProbe")
        try data.write(to: SettingsLeakObserver.journalURL)
        let restored = SettingsLeakObserver.recoverFromKilledTest()
        XCTAssertEqual(Set(restored), [key, "settings.zzKilledProbe"])
        XCTAssertEqual(UserDefaults.standard.object(forKey: key) as? Bool, true)
        XCTAssertNil(UserDefaults.standard.object(forKey: "settings.zzKilledProbe"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: SettingsLeakObserver.journalURL.path))
    }
}
