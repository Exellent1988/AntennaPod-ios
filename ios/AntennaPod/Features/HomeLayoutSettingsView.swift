import SwiftUI

/// Settings → Home layout: show/hide Home sections and drag-reorder (Android HomePreferences lite).
/// Also reachable from the Home tab toolbar (**Configure Home**, Android `configure_home` parity).
/// Supports `.searchable` over section **labels** (case-insensitive, ~250 ms debounce).
/// Toggle still targets the named `HomeSectionId` (safe while filtering). Drag/Edit `.onMove` is
/// disabled while filtering — filtered IndexSet ≠ full `homeSectionOrder` (same honesty as Queue).
/// Reset to defaults always rewrites the **full** layout model (not the filtered subset) after confirm.
/// **Honesty:** only the known `HomeSectionId` cases (Continue, Inbox, Queue, Discover,
/// Recently updated, History, Archived, Favorites, Downloads) — no Statistics / Echo Home section invented.
/// History, Archived, Favorites, and Downloads are optional / off by default.
struct HomeLayoutSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.editMode) private var editMode

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var showResetConfirm = false

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    /// Non-empty debounced query — Edit/`.onMove` disabled (filtered IndexSet ≠ full order).
    private var isFiltering: Bool {
        !debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Drag / Edit reorder allowed only when not filtering.
    private var canReorder: Bool { !isFiltering }

    /// Full layout model — toggles / Reset / (when not filtering) onMove target this list.
    private var allSections: [HomeSectionId] {
        settings.homeSectionOrder
    }

    /// Visible sections; empty query shows the full order. Filters **labels** only (client-side).
    private var filteredSections: [HomeSectionId] {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = allSections
        if q.isEmpty { return base }
        return base.filter { $0.label.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        List {
            if filteredSections.isEmpty {
                ContentUnavailableView(
                    "No matching sections",
                    systemImage: "magnifyingglass",
                    description: Text("No Home layout sections match your search.")
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(localized: "No matching Home layout sections"))
                .accessibilityValue(
                    String(localized: "No Home layout sections match your search. Clear the search or try another section name.")
                )
                .accessibilityHint(
                    String(localized: "Clear the search or try another section name to show Home layout sections again.")
                )
            } else {
                Section {
                    ForEach(filteredSections) { section in
                        Toggle(isOn: Binding(
                            get: { settings.isHomeSectionVisible(section) },
                            set: { settings.setHomeSectionVisible(section, $0) }
                        )) {
                            Label(section.label, systemImage: section.systemImage)
                        }
                        .accessibilityLabel(section.label)
                        .accessibilityValue(visibilityAccessibilityValue(for: section))
                        .accessibilityHint(
                            String(localized: "Shows or hides this section on the Home tab. Order among all sections is changed with Edit drag reorder when search is cleared.")
                        )
                    }
                    .onMove(perform: canReorder ? { source, destination in
                        // Indices are only valid when the list shows the full homeSectionOrder.
                        settings.moveHomeSection(from: source, to: destination)
                    } : nil)
                } header: {
                    Text("Sections")
                } footer: {
                    Text(footerText)
                        .accessibilityLabel(String(localized: "Home layout help"))
                        .accessibilityValue(footerText)
                }
            }

            Section {
                Button("Reset to defaults", role: .destructive) {
                    showResetConfirm = true
                }
                .accessibilityHint(
                    String(localized: "Asks for confirmation, then restores the full default Home section order and visibility, not only the filtered list")
                )
            } footer: {
                Text(String(localized: "Reset restores Discover → Continue → History → Archived → Inbox → Queue → Recently updated → Favorites → Downloads (History, Archived, Favorites, and Downloads hidden). Does not change Home search, subscriptions, queue, or the Downloads tab catalog."))
            }
        }
        .navigationTitle("Home layout")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search sections")
        .onChange(of: searchText) { _, newValue in
            scheduleFilter(for: newValue)
        }
        .onChange(of: isFiltering) { _, filtering in
            // Drag reorder uses full-order indices; leave Edit while a search filter is active.
            if filtering {
                editMode?.wrappedValue = .inactive
            }
        }
        .onDisappear {
            debounceTask?.cancel()
        }
        .confirmationDialog(
            "Reset Home layout?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset to defaults", role: .destructive) {
                editMode?.wrappedValue = .inactive
                settings.resetHomeLayout()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(String(localized: "Restores the full default section order and visibility (History, Archived, Favorites, and Downloads off). Applies to the whole layout — not only rows matching the current search. Home content search, subscriptions, queue, and the Downloads tab catalog are unchanged."))
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
                    // Hide reorder while filtering — filtered IndexSet ≠ full homeSectionOrder.
                    .disabled(allSections.isEmpty || !canReorder)
                    .accessibilityHint(
                        canReorder
                            ? String(localized: "Enables drag reorder of Home sections. Hidden sections stay in the order list so you can place them before showing them again.")
                            : String(localized: "Drag reorder is unavailable while searching; clear the search to reorder")
                    )
            }
        }
    }

    private var footerText: String {
        if isFiltering {
            return String(localized: "Toggle visibility on matching rows. Drag reorder is off while searching (filtered positions would not match the full layout). Empty optional sections (Continue, Inbox, Queue, Recently updated, History, Archived, Favorites, Downloads) still hide on Home when they have no items. Discover always shows its charts preview when enabled. History, Archived, Favorites, and Downloads are off by default.")
        }
        return String(localized: "Toggle visibility and tap Edit to drag-reorder. Empty optional sections (Continue, Inbox, Queue, Recently updated, History, Archived, Favorites, Downloads) still hide on Home when they have no items. Discover always shows its charts preview when enabled. History, Archived, Favorites, and Downloads are off by default.")
    }

    /// VoiceOver value: Visible/Hidden + 1-based position in the full persisted order.
    private func visibilityAccessibilityValue(for section: HomeSectionId) -> String {
        let visible = settings.isHomeSectionVisible(section)
        let visibility = visible
            ? String(localized: "Visible on Home")
            : String(localized: "Hidden on Home")
        guard let index = allSections.firstIndex(of: section) else {
            return visibility
        }
        let position = index + 1
        let total = allSections.count
        let order = String(localized: "Order \(position) of \(total)")
        return "\(visibility). \(order)"
    }

    private func scheduleFilter(for term: String) {
        debounceTask?.cancel()
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            debouncedQuery = ""
            return
        }
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: debounceNs)
            guard !Task.isCancelled else { return }
            debouncedQuery = trimmed
        }
    }
}
