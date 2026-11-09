import PodcastCore
import SwiftUI

/// Podcast settings → Feed URL (Android Feed info → "Edit feed URL", with its warning dialog).
/// Replaces the address and refreshes; episodes, progress, settings and the login stay.
struct FeedURLEditSection: View {
    @EnvironmentObject private var store: PodcastStore
    let feedId: UUID
    @State private var draft = ""
    @State private var showConfirm = false
    @State private var message: String?
    @State private var busy = false

    private var currentUrl: String { store.feeds.first { $0.id == feedId }?.feedUrl ?? "" }

    var body: some View {
        Section {
            TextField(String(localized: "Feed URL"), text: $draft)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onAppear { if draft.isEmpty { draft = currentUrl } }
            Button(String(localized: "Change feed URL")) { showConfirm = true }
                .disabled(busy || draft.trimmingCharacters(in: .whitespaces) == currentUrl)
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
        } header: {
            Text("Feed URL")
        } footer: {
            Text("Only change the address when the podcast moved and the old one no longer works. Episodes, progress and settings are kept.")
        }
        .confirmationDialog(String(localized: "Change feed URL?"), isPresented: $showConfirm, titleVisibility: .visible) {
            Button(String(localized: "Change feed URL"), role: .destructive) { apply() }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text("A wrong address stops updates for this podcast. The podcast is refreshed from the new address.")
        }
    }

    private func apply() {
        busy = true
        Task {
            let outcome = await store.changeFeedUrl(feedId: feedId, to: draft)
            switch outcome {
            case .ok: message = String(localized: "Feed URL changed.")
            case .invalid: message = String(localized: "Enter a valid http or https address.")
            case .unchanged: message = nil
            case .duplicate: message = String(localized: "You are already subscribed to this address.")
            }
            draft = currentUrl == draft.trimmingCharacters(in: .whitespacesAndNewlines) ? currentUrl : draft
            busy = false
        }
    }
}
