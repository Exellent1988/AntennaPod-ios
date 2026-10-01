import SwiftUI

/// Per-subscription overrides (Auto-download / Keep updated / Notifications).
struct PerFeedSettingsView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var appSettings: AppSettings

    let feedId: UUID
    let feedTitle: String

    private var current: FeedSettings {
        store.feedSettings(for: feedId)
    }

    var body: some View {
        Form {
            Section {
                Picker("Auto-download", selection: autoDownloadBinding) {
                    ForEach(PerFeedOverride.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                Text(autoDownloadHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Downloads")
            }

            Section {
                Picker("Keep updated", selection: keepUpdatedBinding) {
                    ForEach(PerFeedOverride.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                Text(keepUpdatedHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Refresh")
            }

            Section {
                Picker("Notify on new episodes", selection: notifyBinding) {
                    ForEach(PerFeedOverride.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                Text(notifyHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Notifications")
            }

            if !current.isDefault {
                Section {
                    Button("Reset to global defaults", role: .destructive) {
                        store.setFeedSettings(.default, for: feedId)
                    }
                }
            }
        }
        .navigationTitle(feedTitle.isEmpty ? "Podcast settings" : feedTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var autoDownloadBinding: Binding<PerFeedOverride> {
        Binding(
            get: { current.autoDownload },
            set: { value in
                store.updateFeedSettings(for: feedId) { $0.autoDownload = value }
            }
        )
    }

    private var keepUpdatedBinding: Binding<PerFeedOverride> {
        Binding(
            get: { current.keepUpdated },
            set: { value in
                store.updateFeedSettings(for: feedId) { $0.keepUpdated = value }
            }
        )
    }

    private var notifyBinding: Binding<PerFeedOverride> {
        Binding(
            get: { current.notifyOnNewEpisodes },
            set: { value in
                store.updateFeedSettings(for: feedId) { $0.notifyOnNewEpisodes = value }
            }
        )
    }

    private var autoDownloadHelp: String {
        let global = appSettings.autoDownloadEnabled ? "on" : "off"
        switch current.autoDownload {
        case .useGlobal:
            return "Follows Settings → Auto-download (currently \(global)). Cap and Wi‑Fi-only still apply globally."
        case .always:
            return "Always enqueue after refresh for this podcast, even when global Auto-download is off. Cap and Wi‑Fi-only still apply."
        case .never:
            return "Never auto-download this podcast, even when global Auto-download is on. Manual Download still works."
        }
    }

    private var keepUpdatedHelp: String {
        switch current.keepUpdated {
        case .useGlobal, .always:
            return "Included when refreshing all feeds (Inbox pull-to-refresh, Keep updated interval, Home refresh). “Always” matches Use global until a global exclude exists."
        case .never:
            return "Skipped during refresh-all. You can still refresh this podcast alone from Subscriptions (swipe) or Add."
        }
    }

    private var notifyHelp: String {
        let global = appSettings.notifyOnNewEpisodes ? "on" : "off"
        switch current.notifyOnNewEpisodes {
        case .useGlobal:
            return "Follows Settings → Notify on new episodes (currently \(global)). System permission still required."
        case .always:
            return "Notify for this podcast even when the global toggle is off (permission still required)."
        case .never:
            return "No local notification for this podcast, even when the global toggle is on."
        }
    }
}
