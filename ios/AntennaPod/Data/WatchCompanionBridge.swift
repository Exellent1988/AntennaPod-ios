import Foundation
import WatchConnectivity

/// iOS side of the Apple Watch companion (beta lite): pushes Continue-listening snapshot via
/// `WCSession.updateApplicationContext` and handles Watch play → `antennapod://play` /
/// `PlaybackDeepLinkRouter`.
final class WatchCompanionBridge: NSObject {
    static let shared = WatchCompanionBridge()

    // MARK: - Lifecycle

    func activateIfNeeded() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        if session.activationState == .notActivated {
            session.activate()
        }
    }

    /// Encode current App Group snapshot (or clear) into Watch applicationContext.
    func pushCurrentSnapshot() {
        activateIfNeeded()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        var context: [String: Any] = [:]
        if let snap = WidgetContinueSnapshot.load(),
           let data = try? JSONEncoder().encode(snap) {
            context[WatchCompanionKeys.snapshotDataKey] = data
        } else {
            context[WatchCompanionKeys.snapshotDataKey] = Data()
        }
        do {
            try session.updateApplicationContext(context)
        } catch {
            // Best-effort; Watch may be unpaired / app not installed / unreachable.
        }
    }

    /// - Parameter completion: Called on main with whether audio is playing after the action.
    ///   Play only resumes an episode that is already loaded, so a Continue snapshot of an
    ///   unloaded episode reports `false` and the Watch must not claim playback.
    private func handleWatchMessage(_ message: [String: Any], completion: ((Bool) -> Void)? = nil) {
        guard let action = message[WatchCompanionKeys.actionKey] as? String,
              action == WatchCompanionKeys.playAction
        else {
            completion?(false)
            return
        }
        DispatchQueue.main.async {
            _ = PlaybackDeepLinkRouter.shared.handle(url: WidgetContinueSnapshot.playURL)
            completion?(PlaybackDeepLinkRouter.shared.playback?.isPlaying == true)
        }
    }
}

extension WatchCompanionBridge: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if activationState == .activated {
            pushCurrentSnapshot()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleWatchMessage(message)
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        handleWatchMessage(message) { isPlaying in
            replyHandler(["ok": isPlaying])
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handleWatchMessage(userInfo)
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        if session.isPaired, session.isWatchAppInstalled {
            pushCurrentSnapshot()
        }
    }
}
