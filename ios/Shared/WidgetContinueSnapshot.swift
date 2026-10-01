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
/// May be stale — not live playback.
struct WidgetContinueSnapshot: Codable, Equatable, Hashable {
    var episodeId: String
    var episodeTitle: String
    var feedTitle: String
    var updatedAtEpochMs: Int64

    /// Deep link opened when the widget is tapped (`PlaybackDeepLinkRouter`); watch Play maps to the same action via WC / openSystemURL.
    static var playURL: URL { URL(string: "antennapod://play")! }

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

/// Builds / publishes the Continue-listening widget snapshot from app-side state.
enum WidgetSnapshotPublisher {
    /// Last published content key (episodeId|title|feed) to avoid thrashing WidgetCenter.
    private static var lastContentKey: String?

    /// Prefer the current player episode when set; else the top in-progress continue item.
    static func publish(
        currentEpisodeId: String?,
        currentEpisodeTitle: String?,
        currentFeedTitle: String?,
        continueEpisodeId: String?,
        continueEpisodeTitle: String?,
        continueFeedTitle: String?
    ) {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let snap: WidgetContinueSnapshot?
        if let id = currentEpisodeId, let title = currentEpisodeTitle, !title.isEmpty {
            snap = WidgetContinueSnapshot(
                episodeId: id,
                episodeTitle: title,
                feedTitle: currentFeedTitle ?? "",
                updatedAtEpochMs: nowMs
            )
        } else if let id = continueEpisodeId, let title = continueEpisodeTitle, !title.isEmpty {
            snap = WidgetContinueSnapshot(
                episodeId: id,
                episodeTitle: title,
                feedTitle: continueFeedTitle ?? "",
                updatedAtEpochMs: nowMs
            )
        } else {
            snap = nil
        }
        let key = snap.map { "\($0.episodeId)|\($0.episodeTitle)|\($0.feedTitle)" }
        if key == lastContentKey { return }
        lastContentKey = key
        WidgetContinueSnapshot.save(snap)
    }
}
