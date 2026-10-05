import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

/// App Group shared between the main app, homescreen WidgetKit extension, and Apple Watch companion.
enum AntennaPodAppGroup {
    /// Must match entitlements on AntennaPod, AntennaPodWidget, and AntennaPodWatch targets.
    static let identifier = "group.de.danoeh.antennapod.ios"
    static let continueSnapshotKey = "widget.continueListening.snapshot.v1"
    /// Widget kind registered in `AntennaPodContinueWidget`.
    static let continueWidgetKind = "AntennaPodContinueListening"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }
}

/// Watch Connectivity keys for Continue-listening snapshot + play remote (phone ↔ watch).
/// App Group UserDefaults is per-device; the phone pushes snapshot bytes via `applicationContext`.
enum WatchCompanionKeys {
    static let snapshotDataKey = AntennaPodAppGroup.continueSnapshotKey
    static let actionKey = "watch.action"
    static let playAction = "play"
}

/// Lightweight Continue-listening payload for the homescreen widget and Apple Watch (App Group UserDefaults).
/// Written by the main app; read by the Widget extension. Watch prefers WC `applicationContext` (App Group alone does not cross devices).
/// May be stale — not live playback. Position/duration are from the same publish moment as title/feed.
struct WidgetContinueSnapshot: Codable, Equatable, Hashable {
    var episodeId: String
    var episodeTitle: String
    var feedTitle: String
    var updatedAtEpochMs: Int64
    /// Saved / live playback position in seconds at publish time (`0` when unknown / start).
    var positionSeconds: Double?
    /// Known duration in seconds at publish time (`nil` / missing / ≤0 = unknown — never invent).
    var durationSeconds: Double?

    /// Deep link opened when the widget is tapped (`PlaybackDeepLinkRouter`); watch Play maps to the same action via WC / openSystemURL.
    static var playURL: URL { URL(string: "antennapod://play")! }

    /// Wall-clock remaining when duration is known: `max(0, duration − position)`. `nil` when duration unknown.
    var remainingSecondsIfKnown: Double? {
        guard let duration = durationSeconds, duration.isFinite, duration > 0 else { return nil }
        let position = positionSeconds ?? 0
        let safePosition = position.isFinite ? max(0, position) : 0
        return max(0, duration - safePosition)
    }

    static func load(from defaults: UserDefaults? = AntennaPodAppGroup.sharedDefaults) -> WidgetContinueSnapshot? {
        guard let defaults,
              let data = defaults.data(forKey: AntennaPodAppGroup.continueSnapshotKey)
        else { return nil }
        return try? JSONDecoder().decode(WidgetContinueSnapshot.self, from: data)
    }

    /// Decode snapshot from Watch Connectivity applicationContext / userInfo payload.
    static func load(fromWatchContext context: [String: Any]) -> WidgetContinueSnapshot? {
        guard let data = context[WatchCompanionKeys.snapshotDataKey] as? Data, !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(WidgetContinueSnapshot.self, from: data)
    }

    /// Persist or clear the snapshot. Reloads WidgetKit timelines when WidgetKit is available.
    static func save(_ snapshot: WidgetContinueSnapshot?, to defaults: UserDefaults? = AntennaPodAppGroup.sharedDefaults) {
        guard let defaults else { return }
        if let snapshot, let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: AntennaPodAppGroup.continueSnapshotKey)
        } else {
            defaults.removeObject(forKey: AntennaPodAppGroup.continueSnapshotKey)
        }
        defaults.synchronize()
        Self.reloadWidgetTimelines()
    }

    static func clear(from defaults: UserDefaults? = AntennaPodAppGroup.sharedDefaults) {
        save(nil, to: defaults)
    }

    static func reloadWidgetTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: AntennaPodAppGroup.continueWidgetKind)
        #endif
    }
}

/// Wall-clock remaining-time labels for the Continue widget / Watch (Shared; not StatisticsView).
/// Same honesty as list bars: never invent duration; `~` when duration unknown; hide when no episode.
enum WidgetRemainingTime {
    /// Human-readable duration (hours / minutes / seconds). Integers via String Catalog (`%lld`).
    static func formatDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return String(localized: "\(hours)h \(minutes)m")
        }
        if minutes > 0 {
            return String(localized: "\(minutes) min")
        }
        if total > 0 {
            return String(localized: "\(total)s")
        }
        return String(localized: "0 min")
    }

    /// Remaining line for one Continue episode: `"Hh Mm left"` when duration known,
    /// `"~"` when duration unknown, `nil` when there is no useful episode context (caller hides).
    static func remainingLabel(for snapshot: WidgetContinueSnapshot) -> String? {
        if let remaining = snapshot.remainingSecondsIfKnown {
            let formatted = formatDuration(remaining)
            return String(localized: "\(formatted) left")
        }
        // Episode present but duration unknown — honest tilde, not invented length.
        return String(localized: "~")
    }

    /// VoiceOver for the remaining line (widget / Watch).
    static func remainingAccessibilityLabel(for snapshot: WidgetContinueSnapshot) -> String {
        if let remaining = snapshot.remainingSecondsIfKnown {
            let formatted = formatDuration(remaining)
            return String(localized: "Remaining time \(formatted). Snapshot wall-clock; may be stale. Not live playback.")
        }
        return String(localized: "Remaining time unknown. Snapshot has no known duration. Not live playback.")
    }
}

/// Builds / publishes the Continue-listening widget snapshot from app-side state.
enum WidgetSnapshotPublisher {
    /// Last published content key (episode + display remaining) to avoid thrashing WidgetCenter / WC.
    private static var lastContentKey: String?

    /// Prefer the current player episode when set; else the top in-progress continue item.
    /// Position/duration are optional wall-clock values from the same moment as title/feed (may be stale).
    static func publish(
        currentEpisodeId: String?,
        currentEpisodeTitle: String?,
        currentFeedTitle: String?,
        currentPositionSeconds: Double?,
        currentDurationSeconds: Double?,
        continueEpisodeId: String?,
        continueEpisodeTitle: String?,
        continueFeedTitle: String?,
        continuePositionSeconds: Double?,
        continueDurationSeconds: Double?
    ) {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let snap: WidgetContinueSnapshot?
        if let id = currentEpisodeId, let title = currentEpisodeTitle, !title.isEmpty {
            snap = WidgetContinueSnapshot(
                episodeId: id,
                episodeTitle: title,
                feedTitle: currentFeedTitle ?? "",
                updatedAtEpochMs: nowMs,
                positionSeconds: currentPositionSeconds,
                durationSeconds: Self.normalizedDuration(currentDurationSeconds)
            )
        } else if let id = continueEpisodeId, let title = continueEpisodeTitle, !title.isEmpty {
            snap = WidgetContinueSnapshot(
                episodeId: id,
                episodeTitle: title,
                feedTitle: continueFeedTitle ?? "",
                updatedAtEpochMs: nowMs,
                positionSeconds: continuePositionSeconds,
                durationSeconds: Self.normalizedDuration(continueDurationSeconds)
            )
        } else {
            snap = nil
        }
        let remainingKey = snap.flatMap { WidgetRemainingTime.remainingLabel(for: $0) } ?? ""
        let key = snap.map { "\($0.episodeId)|\($0.episodeTitle)|\($0.feedTitle)|\(remainingKey)" }
        if key == lastContentKey { return }
        lastContentKey = key
        WidgetContinueSnapshot.save(snap)
    }

    /// Store only finite positive durations; treat ≤0 / non-finite as unknown (`nil`).
    private static func normalizedDuration(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }
}
