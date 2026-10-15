import Foundation
import XCTest

/// Fails any test that leaves persisted app settings (`UserDefaults.standard`, keys under
/// `settings.` and the other app-owned prefixes) different from how it found them. Registered as
/// the test bundle's principal class, so it covers every test without opting in.
final class SettingsLeakObserver: NSObject, XCTestObservation {
    static let watchedPrefixes = ["settings.", "AppSettings", "feedSettings", "playback."]

    private var before: [String: NSObject] = [:]
    static private(set) var current: SettingsLeakObserver?
    /// Every leak seen in this run ("test: key: old → new"); `ZZZSettingsLeakSentinelTests` fails on it.
    static private(set) var leaks: [String] = []

    /// Crash-safe journal: the settings as they were before the running test. A test host that is
    /// killed between setUp and tearDown (another build reinstalling the app, a watchdog, Xcode
    /// stopping the run) never restores them; the next launch of the bundle does.
    static var journalURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("settings-leak-journal.plist")
    }

    override init() {
        super.init()
        // Test hygiene: no audible output from any PlaybackService created in this bundle.
        PlaybackService.silentOutputForTests = true
        XCTestObservationCenter.shared.addTestObserver(self)
        Self.current = self
        Self.recoverFromKilledTest()
    }

    /// Puts back settings a killed test left behind. Returns the keys it restored.
    @discardableResult
    static func recoverFromKilledTest() -> [String] {
        guard let data = try? Data(contentsOf: journalURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let saved = plist["settings"] as? [String: NSObject] else { return [] }
        let restored = restore(saved, over: snapshot())
        if !restored.isEmpty {
            print("SettingsLeakObserver: restored \(restored) left by killed test \(plist["test"] ?? "?")")
        }
        try? FileManager.default.removeItem(at: journalURL)
        return restored
    }

    /// Puts persisted settings back exactly as they were when the running test started. Use it
    /// after `applyBackupSnapshot(original)`: a backup restore writes defaults for keys that were
    /// never set, which this check would report as a leak.
    static func restoreToTestStart() {
        guard let before = current?.before else { return }
        restore(before, over: snapshot())
    }

    @discardableResult
    static func restore(_ saved: [String: NSObject], over current: [String: NSObject]) -> [String] {
        let keys = leakedKeys(before: saved, after: current)
        for key in keys {
            // Only property-list values: UserDefaults raises an Objective-C exception for anything
            // else, and inside an XCTestObservation callback that aborts the whole test host.
            if let v = saved[key], PropertyListSerialization.propertyList(v, isValidFor: .binary) {
                UserDefaults.standard.set(v, forKey: key)
            } else if saved[key] == nil {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        return keys
    }

    static func snapshot() -> [String: NSObject] {
        UserDefaults.standard.dictionaryRepresentation().reduce(into: [:]) { out, pair in
            guard watchedPrefixes.contains(where: { pair.key.hasPrefix($0) }),
                  let value = pair.value as? NSObject else { return }
            out[pair.key] = value
        }
    }

    /// Keys whose value was added, removed or changed.
    static func leakedKeys(before: [String: NSObject], after: [String: NSObject]) -> [String] {
        Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }.sorted()
    }

    func testCaseWillStart(_ testCase: XCTestCase) {
        before = Self.snapshot()
        if let data = try? PropertyListSerialization.data(fromPropertyList: ["test": testCase.name, "settings": before],
                                                          format: .binary, options: 0) {
            try? data.write(to: Self.journalURL, options: .atomic)
        }
        // Never record failures or add teardown blocks from an observer callback: XCTest raises
        // for that outside a running test, and an exception thrown inside XCTestObservationCenter
        // ends in std::terminate (SIGABRT of the whole test host in _testCaseDidStop). Leaks are
        // reported by `ZZZSettingsLeakSentinelTests`, a normal test at the end of the bundle.
    }

    func testCaseDidFinish(_ testCase: XCTestCase) {
        defer { try? FileManager.default.removeItem(at: Self.journalURL) }
        let after = Self.snapshot()
        let leaked = Self.leakedKeys(before: before, after: after)
        guard !leaked.isEmpty else { return }
        let detail = leaked.map { "\($0): \(before[$0].map(String.init(describing:)) ?? "nil") → \(after[$0].map(String.init(describing:)) ?? "nil")" }
        print("SETTINGS LEAK in \(testCase.name): \(detail.joined(separator: ", "))")
        let message = "\(testCase.name) leaked persisted settings: \(detail.joined(separator: ", "))"
        Self.leaks.append(message)
        // Put them back so one leak does not cascade into later tests.
        Self.restore(before, over: after)
    }
}
