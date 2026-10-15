import AudioDSP
import XCTest
@testable import AntennaPod

/// The old Volume adaptation on/off switch (spoken-audio session mode) is merged into the single
/// `volumeAdaptationMode`: legacy **on** with no mode (or `.off`) becomes `.lightBoost`; a stored
/// non-off mode always wins. Same rule for UserDefaults and for restoring older JSON backups.
@MainActor
final class VolumeAdaptationMigrationTests: XCTestCase {
    private let legacyKey = "settings.volumeAdaptationEnabled"
    private let modeKey = "settings.volumeAdaptationMode"
    private var savedLegacy: Any?
    private var savedMode: Any?

    override func setUp() async throws {
        savedLegacy = UserDefaults.standard.object(forKey: legacyKey)
        savedMode = UserDefaults.standard.object(forKey: modeKey)
    }

    override func tearDown() async throws {
        restore(legacyKey, savedLegacy)
        restore(modeKey, savedMode)
    }

    // MARK: Pure rule

    func testMigrationRule() {
        typealias M = AppSettings
        XCTAssertEqual(M.migratedVolumeAdaptationMode(storedMode: nil, legacyEnabled: nil), .off)
        XCTAssertEqual(M.migratedVolumeAdaptationMode(storedMode: nil, legacyEnabled: false), .off)
        XCTAssertEqual(M.migratedVolumeAdaptationMode(storedMode: nil, legacyEnabled: true), .lightBoost)
        XCTAssertEqual(M.migratedVolumeAdaptationMode(storedMode: "off", legacyEnabled: true), .lightBoost)
        XCTAssertEqual(M.migratedVolumeAdaptationMode(storedMode: "garbage", legacyEnabled: true), .lightBoost)
        XCTAssertEqual(M.migratedVolumeAdaptationMode(storedMode: "heavyReduction", legacyEnabled: true), .heavyReduction)
        XCTAssertEqual(M.migratedVolumeAdaptationMode(storedMode: "mediumBoost", legacyEnabled: false), .mediumBoost)
    }

    // MARK: UserDefaults

    func testUserDefaultsLegacyOnWithoutModeMigratesToLightBoostAndDropsOldKey() {
        UserDefaults.standard.set(true, forKey: legacyKey)
        UserDefaults.standard.removeObject(forKey: modeKey)
        let settings = AppSettings()
        XCTAssertEqual(settings.volumeAdaptationMode, .lightBoost)
        XCTAssertNil(UserDefaults.standard.object(forKey: legacyKey), "Old switch must be removed after migration")
        XCTAssertEqual(UserDefaults.standard.string(forKey: modeKey), "lightBoost")
        XCTAssertEqual(AppSettings().volumeAdaptationMode, .lightBoost, "Migration is stable on the next launch")
    }

    func testUserDefaultsLegacyOnWithModeOffMigratesToLightBoost() {
        UserDefaults.standard.set(true, forKey: legacyKey)
        UserDefaults.standard.set("off", forKey: modeKey)
        XCTAssertEqual(AppSettings().volumeAdaptationMode, .lightBoost)
    }

    func testUserDefaultsExistingModeWinsOverLegacySwitch() {
        UserDefaults.standard.set(true, forKey: legacyKey)
        UserDefaults.standard.set("heavyBoost", forKey: modeKey)
        XCTAssertEqual(AppSettings().volumeAdaptationMode, .heavyBoost)
        XCTAssertNil(UserDefaults.standard.object(forKey: legacyKey))
    }

    func testUserDefaultsLegacyOffKeepsOff() {
        UserDefaults.standard.set(false, forKey: legacyKey)
        UserDefaults.standard.removeObject(forKey: modeKey)
        XCTAssertEqual(AppSettings().volumeAdaptationMode, .off)
        XCTAssertNil(UserDefaults.standard.object(forKey: legacyKey))
    }

    // MARK: JSON backup

    func testOldBackupWithSwitchOnRestoresAsLightBoost() throws {
        let settings = AppSettings()
        let original = settings.backupSnapshot()
        defer { settings.applyBackupSnapshot(original); SettingsLeakObserver.restoreToTestStart() }
        settings.applyBackupSnapshot(try oldBackup(legacyEnabled: true, mode: nil))
        XCTAssertEqual(settings.volumeAdaptationMode, .lightBoost)
        settings.applyBackupSnapshot(try oldBackup(legacyEnabled: true, mode: "off"))
        XCTAssertEqual(settings.volumeAdaptationMode, .lightBoost)
    }

    func testOldBackupModeWinsAndSwitchOffKeepsOff() throws {
        let settings = AppSettings()
        let original = settings.backupSnapshot()
        defer { settings.applyBackupSnapshot(original); SettingsLeakObserver.restoreToTestStart() }
        settings.applyBackupSnapshot(try oldBackup(legacyEnabled: true, mode: "lightReduction"))
        XCTAssertEqual(settings.volumeAdaptationMode, .lightReduction)
        settings.applyBackupSnapshot(try oldBackup(legacyEnabled: false, mode: nil))
        XCTAssertEqual(settings.volumeAdaptationMode, .off)
    }

    func testNewBackupNoLongerWritesTheOldSwitch() throws {
        let settings = AppSettings()
        let original = settings.backupSnapshot()
        defer { settings.applyBackupSnapshot(original); SettingsLeakObserver.restoreToTestStart() }
        settings.volumeAdaptationMode = .mediumBoost
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings.backupSnapshot())) as? [String: Any]
        XCTAssertNil(json?["volumeAdaptationEnabled"])
        XCTAssertEqual(json?["volumeAdaptationMode"] as? String, "mediumBoost")
        let restored = try JSONDecoder().decode(AppSettingsBackupSnapshot.self,
                                                from: JSONEncoder().encode(settings.backupSnapshot()))
        settings.volumeAdaptationMode = .off
        settings.applyBackupSnapshot(restored)
        XCTAssertEqual(settings.volumeAdaptationMode, .mediumBoost)
    }

    /// A current backup rewritten to look like one from before the merge.
    private func oldBackup(legacyEnabled: Bool, mode: String?) throws -> AppSettingsBackupSnapshot {
        let data = try JSONEncoder().encode(AppSettings().backupSnapshot())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["volumeAdaptationEnabled"] = legacyEnabled
        json["volumeAdaptationMode"] = mode
        if mode == nil { json.removeValue(forKey: "volumeAdaptationMode") }
        return try JSONDecoder().decode(AppSettingsBackupSnapshot.self,
                                        from: JSONSerialization.data(withJSONObject: json))
    }

    private func restore(_ key: String, _ value: Any?) {
        if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
    }
}
