import SwiftUI

/// Settings → Reset app data (Android: clearing app storage, then sync pulls the subscriptions
/// again). Clears subscriptions, episodes, queue, downloads, playback state and caches; keeps the
/// gpodder / Nextcloud login (Keychain) and re-imports the subscriptions when logged in.
struct ResetAppDataSection: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var gpodder: GpodderSyncService
    @State private var showConfirm = false
    @State private var isBusy = false

    var body: some View {
        Section {
            Button(role: .destructive) {
                showConfirm = true
            } label: {
                Label("Reset app data", systemImage: "trash")
            }
            .disabled(isBusy)
            .accessibilityHint(String(localized: "Deletes subscriptions, episodes, queue, downloads and playback progress. Your sync login is kept."))
            Text(helpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .confirmationDialog("Reset app data?", isPresented: $showConfirm, titleVisibility: .visible) {
            Button("Reset app data", role: .destructive) { reset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(helpText)
        }
    }

    private var helpText: String {
        gpodder.isLoggedIn
            ? String(localized: "Deletes subscriptions, episodes, queue, downloads, playback progress and caches. Your sync login is kept and your subscriptions are downloaded again from the sync server.")
            : String(localized: "Deletes subscriptions, episodes, queue, downloads, playback progress and caches. Settings are kept. This cannot be undone.")
    }

    private func reset() {
        isBusy = true
        store.resetAppData()
        Task {
            await gpodder.reimportAfterReset(store: store)
            isBusy = false
        }
    }
}
