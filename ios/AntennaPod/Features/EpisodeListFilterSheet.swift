import PodcastCore
import SwiftUI

/// Android episode filter dialog (pairs of exclusive chips) + sort list, as a sheet.
struct EpisodeListFilterSheet: View {
    let title: String
    @Binding var options: EpisodeListOptions
    var allowsFilter: Bool = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if allowsFilter {
                    Section {
                        ForEach(EpisodeFilterToken.groups, id: \.0) { pair in
                            HStack(spacing: 8) {
                                chip(pair.0)
                                chip(pair.1)
                            }
                        }
                    } header: {
                        Text("Filter")
                    } footer: {
                        Text("Choose at most one per row. All chosen conditions must match. Applies on top of the chips above the list.")
                    }
                }
                Section {
                    Picker("Sort", selection: $options.sort) {
                        Text("Screen default").tag(EpisodeListSortOrder?.none)
                        ForEach(EpisodeListSortOrder.allCases, id: \.self) { order in
                            Text(order.label).tag(EpisodeListSortOrder?.some(order))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Sort")
                } footer: {
                    Text("Unknown dates, durations and sizes are listed last.")
                }
                if !options.isDefault {
                    Section {
                        Button("Reset filter and sort", role: .destructive) { options = .init() }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func chip(_ token: EpisodeFilterToken) -> some View {
        let on = options.filter.tokens.contains(token)
        return Button {
            options.filter.toggle(token)
        } label: {
            Text(token.label)
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(on ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12), in: Capsule())
                .overlay(Capsule().stroke(on ? Color.accentColor : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Toolbar button that opens `EpisodeListFilterSheet`; filled icon when anything is set.
struct EpisodeListFilterToolbarModifier: ViewModifier {
    let title: String
    @Binding var options: EpisodeListOptions
    var allowsFilter: Bool
    @State private var showSheet = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSheet = true
                    } label: {
                        Label(allowsFilter ? "Filter and sort" : "Sort",
                              systemImage: options.isDefault ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityIdentifier("episodeListFilterButton")
                    .accessibilityValue(options.isDefault ? String(localized: "Off") : String(localized: "On"))
                }
            }
            .sheet(isPresented: $showSheet) {
                EpisodeListFilterSheet(title: title, options: $options, allowsFilter: allowsFilter)
            }
            #if DEBUG
            .task {
                guard UserDefaults.standard.bool(forKey: "APDebugOpenFilterSheet") else { return }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                showSheet = true
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                PlayerDebugLaunch.scrollPresentedList()
            }
            #endif
    }
}

extension View {
    func episodeListFilterToolbar(_ title: String, options: Binding<EpisodeListOptions>, allowsFilter: Bool = true) -> some View {
        modifier(EpisodeListFilterToolbarModifier(title: title, options: options, allowsFilter: allowsFilter))
    }

    /// Android Queue "Keep sorted" menu (sort order + checkbox).
    func queueKeepSortedToolbar() -> some View { modifier(QueueKeepSortedToolbarModifier()) }
}

struct QueueKeepSortedToolbarModifier: ViewModifier {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var settings: AppSettings
    @State private var lastOrder: EpisodeListSortOrder = .dateNewOld

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Keep sorted", isOn: Binding(
                        get: { settings.queueKeepSortedOrder != nil },
                        set: { settings.queueKeepSortedOrder = $0 ? lastOrder : nil; store.applyQueueKeepSorted() }
                    ))
                    Picker("Order", selection: Binding(
                        get: { settings.queueKeepSortedOrder ?? lastOrder },
                        set: { lastOrder = $0; if settings.queueKeepSortedOrder != nil { settings.queueKeepSortedOrder = $0; store.applyQueueKeepSorted() } }
                    )) {
                        ForEach(EpisodeListSortOrder.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                } label: {
                    Label("Keep sorted", systemImage: settings.queueKeepSortedOrder == nil ? "arrow.up.arrow.down.circle" : "arrow.up.arrow.down.circle.fill")
                }
                .accessibilityIdentifier("queueKeepSortedMenu")
                .accessibilityHint(String(localized: "When on, the queue stays sorted by the chosen order after every change and manual reordering is off."))
            }
        }
    }
}
