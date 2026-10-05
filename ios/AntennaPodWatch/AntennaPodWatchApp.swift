import SwiftUI
import WatchConnectivity
import WatchKit

@main
struct AntennaPodWatchApp: App {
    @StateObject private var model = WatchContinueModel()

    var body: some Scene {
        WindowGroup {
            ContinueListeningWatchView(model: model)
        }
    }
}

/// Loads Continue-listening from WC applicationContext (preferred) or App Group (usually empty on watch).
@MainActor
final class WatchContinueModel: NSObject, ObservableObject {
    @Published private(set) var snapshot: WidgetContinueSnapshot?
    @Published private(set) var statusMessage: String?

    override init() {
        super.init()
        refreshFromLocalSources()
        activateSession()
    }

    func refreshFromLocalSources() {
        if let fromGroup = WidgetContinueSnapshot.load() {
            snapshot = fromGroup
            return
        }
        if WCSession.isSupported() {
            snapshot = WidgetContinueSnapshot.load(fromWatchContext: WCSession.default.receivedApplicationContext)
        }
    }

    func activateSession() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Remote play on companion iPhone via Watch Connectivity; falls back to openSystemURL(`antennapod://play`).
    func playOnPhone() {
        statusMessage = nil
        let url = WidgetContinueSnapshot.playURL
        let payload: [String: Any] = [WatchCompanionKeys.actionKey: WatchCompanionKeys.playAction]

        guard WCSession.isSupported() else {
            WKApplication.shared().openSystemURL(url)
            statusMessage = String(localized: "Opening iPhone…")
            return
        }

        let session = WCSession.default
        if session.activationState == .activated, session.isReachable {
            session.sendMessage(payload, replyHandler: { [weak self] reply in
                // The phone answers `ok: false` when no episode is loaded there, so nothing plays.
                let isPlaying = (reply["ok"] as? Bool) ?? false
                Task { @MainActor in
                    self?.statusMessage = isPlaying
                        ? String(localized: "Playing on iPhone")
                        : String(localized: "Open AntennaPod on iPhone to continue")
                }
            }, errorHandler: { [weak self] _ in
                Task { @MainActor in
                    self?.fallbackOpenOrTransfer(url: url, payload: payload)
                }
            })
        } else {
            fallbackOpenOrTransfer(url: url, payload: payload)
        }
    }

    private func fallbackOpenOrTransfer(url: URL, payload: [String: Any]) {
        // openSystemURL is reliable for http(s)/tel/sms; custom schemes are best-effort for companion apps.
        WKApplication.shared().openSystemURL(url)
        if WCSession.isSupported(), WCSession.default.activationState == .activated {
            WCSession.default.transferUserInfo(payload)
        }
        statusMessage = String(localized: "Opening iPhone…")
    }
}

extension WatchContinueModel: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            refreshFromLocalSources()
            if let snap = WidgetContinueSnapshot.load(fromWatchContext: session.receivedApplicationContext) {
                snapshot = snap
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            snapshot = WidgetContinueSnapshot.load(fromWatchContext: applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            if let snap = WidgetContinueSnapshot.load(fromWatchContext: userInfo) {
                snapshot = snap
            }
        }
    }
}
