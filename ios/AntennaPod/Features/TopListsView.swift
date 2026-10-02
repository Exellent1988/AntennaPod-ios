import SwiftUI

/// Apple iTunes top podcast charts (Quick discovery). Pull-to-refresh; Preview → Confirm Subscribe.
struct TopListsView: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var parental: ParentalControls

    @State private var results: [ItunesPodcastResult] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var didLoad = false
    @State private var previewRequest: FeedPreviewRequest?

    private let service = ItunesTopListService()

    private var countryCode: String {
        settings.resolvedChartsCountryCode
    }

    private var countryLabel: String {
        let code = countryCode.uppercased()
        let name = Locale.current.localizedString(forRegionCode: code) ?? code
        return "\(name) (\(code))"
    }

    private var chartsHelpText: String {
        let template = String(
            localized: "Top podcasts on Apple Charts for %@. No API key — public iTunes RSS. Change country under Settings → Discovery."
        )
        return String(format: template, locale: .current, countryLabel)
    }

    /// VoiceOver for the full Discover empty list. Visible copy stays concise; this names Apple
    /// charts versus the Home preview, the library, and other directories, and whether the
    /// explicit filter is actually on. Does not invent chart rows.
    private var discoverEmptyAccessibilityValue: String {
        if parental.shouldHideExplicitCharts {
            return String(
                localized: "Full Discover charts returned no podcasts with a resolved RSS feed URL for the selected country. This is Apple iTunes charts, not the Home preview, not your subscriptions, and not Podcast Index or fyyd. Parental controls requested non-explicit charts, so shows can be hidden. Changing the chart count does not invent results."
            )
        }
        return String(
            localized: "Full Discover charts returned no podcasts with a resolved RSS feed URL for the selected country. This is Apple iTunes charts, not the Home preview, not your subscriptions, and not Podcast Index or fyyd. Hide explicit top charts is off, so this is not an explicit filter. Rows without a feed URL are omitted. Changing the chart count does not invent results."
        )
    }

    private var discoverEmptyAccessibilityHint: String {
        if parental.shouldHideExplicitCharts {
            return String(
                localized: "Change the charts country under Settings → Discovery, or turn off Hide explicit top charts in parental controls. This empty list is not a subscription search."
            )
        }
        return String(
            localized: "Change the charts country under Settings → Discovery. This empty list is not a subscription search."
        )
    }

    var body: some View {
        List {
            Section {
                Text(chartsHelpText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(chartsHelpText)
                    .accessibilityHint(
                        String(localized: "Explains the chart source and where to change the country")
                    )
            }

            if let loadError {
                Section {
                    Text(loadError)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            String(localized: "Chart loading error") + ", " + loadError
                        )
                    Button("Retry") {
                        Task { await loadCharts() }
                    }
                    .accessibilityHint(String(localized: "Loads the podcast charts again"))
                }
            }

            if didLoad && !isLoading && results.isEmpty && loadError == nil {
                Section {
                    ContentUnavailableView(
                        "No chart results",
                        systemImage: "chart.bar",
                        description: Text("iTunes returned no podcasts for this country, or feed URLs could not be resolved. Try another country in Settings.")
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized: "No chart results"))
                    .accessibilityValue(discoverEmptyAccessibilityValue)
                    .accessibilityHint(discoverEmptyAccessibilityHint)
                    .listRowBackground(Color.clear)
                }
            }

            if !results.isEmpty {
                Section(String(localized: "Top \(results.count)")) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                        DiscoveryResultRow(
                            title: "\(index + 1). \(item.title)",
                            author: item.author,
                            artworkURL: item.artworkURL,
                            feedUrl: item.feedUrl,
                            isSubscribed: store.feeds.contains { $0.feedUrl == item.feedUrl },
                            onSelect: {
                                previewRequest = FeedPreviewRequest(
                                    feedUrl: item.feedUrl,
                                    hintTitle: item.title,
                                    hintAuthor: item.author,
                                    hintArtworkURL: item.artworkURL
                                )
                            }
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Discover")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $previewRequest) { request in
            FeedPreviewView(request: request)
        }
        .overlay {
            if isLoading && results.isEmpty {
                ProgressView("Loading charts…")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized: "Loading podcast charts"))
                    .accessibilityAddTraits(.updatesFrequently)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .refreshable {
            await loadCharts()
        }
        .task {
            if !didLoad {
                await loadCharts()
            }
        }
        .onChange(of: settings.chartsCountryCode) { _, _ in
            Task { await loadCharts() }
        }
        .onChange(of: settings.discoverChartsLimit) { _, _ in
            Task { await loadCharts() }
        }
        .onChange(of: parental.hideExplicitCharts) { _, _ in
            Task { await loadCharts() }
        }
        .onChange(of: parental.isEnabled) { _, _ in
            Task { await loadCharts() }
        }
    }

    @MainActor
    private func loadCharts() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let found = try await service.loadTopList(
                country: countryCode,
                limit: settings.discoverChartsLimit.rowCap,
                includeExplicit: !parental.shouldHideExplicitCharts
            )
            results = found
            didLoad = true
        } catch is CancellationError {
            // ignore
        } catch {
            results = []
            didLoad = true
            loadError = error.localizedDescription
        }
    }
}

/// Compact Home preview of top charts (Quick discovery). Soft-cap via `homeDiscoverPreviewLimit`
/// (not full TopListsView / `discoverChartsLimit`).
struct HomeTopListsPreview: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var parental: ParentalControls

    @State private var preview: [ItunesPodcastResult] = []
    @State private var loadError: String?
    @State private var isLoading = false
    @State private var didLoad = false

    private let service = ItunesTopListService()

    /// Soft-cap from `AppSettings.homeDiscoverPreviewLimit` (3/5/8/10, default 5). Full Discover /
    /// TopListsView uses `AppSettings.discoverChartsLimit` (`DiscoverChartsLimit` 10/25/50/100, default 25).
    private var limit: Int {
        let allowed = Set(HomePreviewLimit.allCases.map(\.rawValue))
        let raw = settings.homeDiscoverPreviewLimit.rawValue
        return allowed.contains(raw) ? raw : HomePreviewLimit.five.rawValue
    }

    var body: some View {
        Group {
            if isLoading && preview.isEmpty && loadError == nil {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading charts…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "Loading podcast chart preview"))
                .accessibilityAddTraits(.updatesFrequently)
            } else if let loadError, preview.isEmpty {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        String(localized: "Podcast chart preview unavailable") + ", " + loadError
                    )
                    .accessibilityHint(String(localized: "Open Discover to try loading charts again"))
            } else if didLoad && preview.isEmpty {
                Text("No chart results")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized: "No podcast chart preview results"))
                    .accessibilityValue(
                        String(localized: "Apple Charts returned no podcasts for the selected country")
                    )
            } else if !preview.isEmpty {
                ForEach(Array(preview.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                            Text(item.author)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if store.feeds.contains(where: { $0.feedUrl == item.feedUrl }) {
                            Text("Subscribed")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        previewAccessibilityLabel(
                            index: index,
                            item: item,
                            isSubscribed: store.feeds.contains { $0.feedUrl == item.feedUrl }
                        )
                    )
                }
            }
        }
        .task {
            await loadPreview()
        }
        .onChange(of: settings.chartsCountryCode) { _, _ in
            Task { await loadPreview() }
        }
        .onChange(of: settings.homeDiscoverPreviewLimit) { _, _ in
            Task { await loadPreview() }
        }
        .onChange(of: parental.hideExplicitCharts) { _, _ in
            Task { await loadPreview() }
        }
        .onChange(of: parental.isEnabled) { _, _ in
            Task { await loadPreview() }
        }
    }

    private func previewAccessibilityLabel(
        index: Int,
        item: ItunesPodcastResult,
        isSubscribed: Bool
    ) -> String {
        var parts = [String(localized: "Chart position") + " \(index + 1)", item.title]
        if !item.author.isEmpty {
            parts.append(item.author)
        }
        if isSubscribed {
            parts.append(String(localized: "Subscribed"))
        }
        return parts.joined(separator: ", ")
    }

    @MainActor
    private func loadPreview() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let found = try await service.loadTopList(
                country: settings.resolvedChartsCountryCode,
                limit: limit,
                includeExplicit: !parental.shouldHideExplicitCharts
            )
            preview = found
            didLoad = true
        } catch is CancellationError {
            // ignore
        } catch {
            preview = []
            didLoad = true
            loadError = error.localizedDescription
        }
    }
}
