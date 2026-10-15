import Foundation
import PodcastCore
import SwiftUI

/// One place that answers "may this use mobile data now?" (Android `NetworkUtils` +
/// `prefMobileUpdateTypes`). Wi‑Fi / Ethernet always pass; before the first path sample the gate
/// is optimistic (same as the existing Wi‑Fi-only toggles).
@MainActor
enum MobileDataGate {
    /// Test seam: (offline, unmetered). nil → `NetworkPathGate`.
    static var pathOverrideForTests: (offline: Bool, unmetered: Bool)?

    private static func path() -> (offline: Bool, unmetered: Bool)? {
        if let o = pathOverrideForTests { return o }
        let gate = NetworkPathGate.shared
        gate.startIfNeeded()
        guard gate.hasReportedPath else { return nil }
        return (!gate.pathSatisfied, gate.isWifiOrEthernet)
    }

    /// Strict: offline → false.
    static func allows(_ type: MobileUpdateType, settings: AppSettings? = nil) -> Bool {
        guard let settings = settings ?? AppServices.settings, let p = path() else { return true }
        return MobileUpdateTypes.allows(type, in: settings.mobileUpdateTypes, isOffline: p.offline, isUnmetered: p.unmetered)
    }

    /// Only the mobile-data rule (offline is not this gate's business, the request fails as before).
    static func allowsIgnoringOffline(_ type: MobileUpdateType, settings: AppSettings? = nil) -> Bool {
        guard let settings = settings ?? AppServices.settings, let p = path() else { return true }
        return MobileUpdateTypes.allows(type, in: settings.mobileUpdateTypes, isOffline: false, isUnmetered: p.unmetered)
    }

    /// Central image request (AppAsyncImage + lock-screen artwork). Android `images` not allowed on
    /// mobile data (or offline) → cached response only, no network fetch.
    static func imageRequest(for url: URL, settings: AppSettings? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        if !allows(.images, settings: settings) {
            request.cachePolicy = .returnCacheDataDontLoad
        }
        return request
    }
}

/// Android "Refresh over mobile data?" for a user-started refresh that the Mobile updates setting
/// blocks: Refresh anyway (once) / Always allow (adds feed refresh) / Cancel.
struct MobileRefreshPromptModifier: ViewModifier {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var settings: AppSettings

    func body(content: Content) -> some View {
        content.alert(String(localized: "Refresh over mobile data?"), isPresented: $store.mobileRefreshPrompt) {
            Button(String(localized: "Refresh anyway")) {
                Task { await store.refreshAllFeeds(allowMobileOnce: true) }
            }
            Button(String(localized: "Always allow")) {
                settings.setAllowedOnMobile(.feedRefresh, true)
                Task { await store.refreshAllFeeds() }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text("Feed refresh Wi‑Fi only is on in Settings → Network / Downloads, so feeds are not refreshed over mobile data.")
        }
    }
}
