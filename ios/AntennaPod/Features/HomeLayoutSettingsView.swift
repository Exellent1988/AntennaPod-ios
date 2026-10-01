import SwiftUI

/// Settings → Home layout: show/hide Home sections and drag-reorder (Android HomePreferences lite).
struct HomeLayoutSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        List {
            Section {
                ForEach(settings.homeSectionOrder) { section in
                    Toggle(isOn: Binding(
                        get: { settings.isHomeSectionVisible(section) },
                        set: { settings.setHomeSectionVisible(section, $0) }
                    )) {
                        Label(section.label, systemImage: section.systemImage)
                    }
                }
                .onMove { source, destination in
                    settings.moveHomeSection(from: source, to: destination)
                }
            } header: {
                Text("Sections")
            } footer: {
                Text("Toggle visibility and tap Edit to drag-reorder. Empty optional sections (Continue, Inbox, Queue, Recently updated, Favorites) still hide on Home when they have no items. Discover always shows its charts preview when enabled. Favorites is off by default.")
            }

            Section {
                Button("Reset to defaults") {
                    settings.resetHomeLayout()
                }
            }
        }
        .navigationTitle("Home layout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
    }
}
