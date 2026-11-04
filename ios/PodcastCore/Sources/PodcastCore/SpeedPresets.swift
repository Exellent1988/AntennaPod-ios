import Foundation

/// Android `UserPreferences.prefPlaybackSpeedArray`: the user-editable speed chips of the
/// variable speed dialog. Stored as a JSON array of "0.00" strings (Android
/// `setPlaybackSpeedArray`, Locale.US); defaults to [1.00, 1.25, 1.50] when never set.
/// The dialog's "+" chip adds the current speed (no duplicates, kept sorted ascending);
/// long-press on a chip removes it.
public enum SpeedPresets {
    /// UserDefaults key (prefix `settings.` → watched by the settings leak check).
    public static let defaultsKey = "settings.playbackSpeedPresets"
    /// Android default when the pref was never written.
    public static let androidDefault: [Float] = [1.0, 1.25, 1.5]
    /// Fixed list of iOS builds before the editor; kept for existing installs (no silent change).
    public static let legacyIOSDefault: [Float] = [0.8, 1.0, 1.1, 1.2, 1.3, 1.5, 2.0]
    /// iOS AVPlayer custom range (Android allows up to 3.5×; iOS stays at its 3.0× cap).
    public static let range: ClosedRange<Float> = 0.5...3.0
    public static let step: Float = 0.05

    /// Round to the 0.05 grid inside `range` (Android stores two decimals); nil when invalid.
    public static func normalized(_ speed: Float) -> Float? {
        guard speed.isFinite, speed >= range.lowerBound - 0.001, speed <= range.upperBound + 0.001 else { return nil }
        let stepped = (speed / step).rounded() * step
        let rounded = (stepped * 100).rounded() / 100
        return min(max(rounded, range.lowerBound), range.upperBound)
    }

    /// Normalized, de-duplicated, ascending (Android sorts after every add).
    public static func sanitized(_ speeds: [Float]) -> [Float] {
        var out: [Float] = []
        for s in speeds.compactMap(normalized) where !out.contains(where: { abs($0 - s) < 0.001 }) {
            out.append(s)
        }
        return out.sorted()
    }

    public static func contains(_ speed: Float, in list: [Float]) -> Bool {
        list.contains { abs($0 - speed) < 0.001 }
    }

    /// Android "+" chip: add the speed unless already present. `added == false` → "preset already exists".
    public static func adding(_ speed: Float, to list: [Float]) -> (list: [Float], added: Bool) {
        guard let s = normalized(speed) else { return (list, false) }
        if contains(s, in: list) { return (list, false) }
        return (sanitized(list + [s]), true)
    }

    /// Long-press removal. iOS keeps at least one chip (tap-to-cycle needs a list).
    public static func removing(_ speed: Float, from list: [Float]) -> (list: [Float], removed: Bool) {
        guard list.count > 1, contains(speed, in: list) else { return (list, false) }
        return (list.filter { abs($0 - speed) >= 0.001 }, true)
    }

    /// Tap on the speed button: next preset after the current rate, wrapping; a rate between
    /// presets goes to the next higher one (first one when above all).
    public static func next(after rate: Float, in list: [Float]) -> Float? {
        guard !list.isEmpty else { return nil }
        if let i = list.firstIndex(where: { abs($0 - rate) < 0.001 }) {
            return list[(i + 1) % list.count]
        }
        return list.first(where: { $0 > rate }) ?? list[0]
    }

    /// Android JSON form: ["1.00","1.25","1.50"].
    public static func encode(_ list: [Float]) -> String {
        let items = sanitized(list).map { "\"" + String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), $0) + "\"" }
        return "[" + items.joined(separator: ",") + "]"
    }

    /// Accepts Android strings or plain numbers. Invalid / empty → nil (caller uses its default).
    public static func decode(_ json: String) -> [Float]? {
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return nil }
        let values: [Float] = array.compactMap { item in
            if let s = item as? String { return Float(s) }
            if let n = item as? NSNumber { return n.floatValue }
            return nil
        }
        let list = sanitized(values)
        return list.isEmpty ? nil : list
    }

    /// Stored list; never written → Android default for a fresh install, the legacy iOS list
    /// when the app already had data (an update keeps the chips the user knew).
    public static func load(from defaults: UserDefaults = .standard, hasExistingData: Bool) -> [Float] {
        if let raw = defaults.string(forKey: defaultsKey), let list = decode(raw) { return list }
        return hasExistingData ? legacyIOSDefault : androidDefault
    }

    public static func save(_ list: [Float], to defaults: UserDefaults = .standard) {
        defaults.set(encode(list), forKey: defaultsKey)
    }
}
