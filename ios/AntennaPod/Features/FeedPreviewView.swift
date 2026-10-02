import SwiftUI

/// Identifiable request to preview a feed before subscribe (discovery / URL).
struct FeedPreviewRequest: Identifiable, Hashable {
    var id: String { feedUrl.lowercased() }
    let feedUrl: String
    var hintTitle: String?
    var hintAuthor: String?
    var hintArtworkURL: URL?

    init(
        feedUrl: String,
        hintTitle: String? = nil,
        hintAuthor: String? = nil,
        hintArtworkURL: URL? = nil
    ) {
        self.feedUrl = feedUrl
        self.hintTitle = hintTitle
        self.hintAuthor = hintAuthor
        self.hintArtworkURL = hintArtworkURL
    }
}

/// Online feed preview: fetch+parse via `FeedRepository`, show metadata + first episodes, then Confirm Subscribe / Open / Cancel.
/// Reused by discovery rows and Add → URL (including clipboard). Honest timeout / network / not-a-feed errors.
struct FeedPreviewView: View {
    @EnvironmentObject private var store: PodcastStore
    @Environment(\.dismiss) private var dismiss

    let request: FeedPreviewRequest
    /// Called after a successful subscribe (e.g. dismiss Add sheet).
    var onSubscribed: (() -> Void)? = nil

    @State private var parsed: PodcastFeed?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var isSubscribing = false
    @State private var openFeed: PodcastFeed?

    private let repository = FeedRepository()
    private let previewEpisodeLimit = 10

    private var subscribedFeed: PodcastFeed? {
        FeedURLNormalization.subscribedFeed(matching: request.feedUrl, in: store.feeds)
    }

    private var isAlreadySubscribed: Bool {
        subscribedFeed != nil
    }

    private var displayTitle: String {
        parsed?.title.nilIfEmpty ?? request.hintTitle?.nilIfEmpty ?? "Podcast"
    }

    private var displayAuthor: String? {
        // Prefer author from the fetched feed when present; else discovery hint (iTunes/Index/fyyd).
        parsed?.displayAuthor ?? request.hintAuthor?.nilIfEmpty
    }

    private var displayArtworkURL: URL? {
        if let s = parsed?.preferredDisplayArtworkURL?.nilIfEmpty, let u = URL(string: s) { return u }
        if let s = parsed?.imageUrl?.nilIfEmpty, let u = URL(string: s) { return u }
        return request.hintArtworkURL
    }

    private var episodeCount: Int {
        parsed?.episodes.count ?? 0
    }

    private var previewEpisodes: [PodcastEpisode] {
        Array((parsed?.episodes ?? []).prefix(previewEpisodeLimit))
    }

    var body: some View {
        List {
            Section {
                header
            }

            if isLoading && parsed == nil {
                Section {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading feed…")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let loadError {
                Section {
                    Text(loadError)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                        .accessibilityLabel(loadError)
                    Button("Retry") {
                        Task { await loadPreview() }
                    }
                    .accessibilityHint(String(localized: "Fetches the feed URL again"))
                } footer: {
                    Text("Preview could not load this URL. Check the address, network, or try again — this is not a subscribe yet.")
                }
            }

            if let parsed {
                Section {
                    LabeledContent("Episodes", value: "\(episodeCount)")
                    if let site = parsed.siteLink?.nilIfEmpty {
                        Text(site)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                } header: {
                    Text("Feed")
                }

                if !previewEpisodes.isEmpty {
                    Section {
                        ForEach(previewEpisodes) { ep in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ep.title)
                                    .font(.subheadline)
                                    .lineLimit(2)
                                if let ms = ep.pubDateEpochMs {
                                    Text(Self.shortDate(ms))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text(
                            episodeCount > previewEpisodeLimit
                                ? "Latest \(previewEpisodeLimit) episodes"
                                : "Episodes"
                        )
                    } footer: {
                        if episodeCount > previewEpisodeLimit {
                            Text("Showing \(previewEpisodeLimit) of \(episodeCount). Subscribe to see the full list.")
                        }
                    }
                } else if loadError == nil && !isLoading {
                    Section {
                        Text("No episodes found in this feed.")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                }
            }

            Section {
                if isAlreadySubscribed {
                    Button {
                        if let feed = subscribedFeed {
                            openFeed = feed
                        }
                    } label: {
                        Text("Open feed")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(subscribedFeed == nil)
                    .accessibilityHint(String(localized: "Opens the existing subscription instead of subscribing again"))
                } else {
                    Button {
                        Task { await confirmSubscribe() }
                    } label: {
                        if isSubscribing || store.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .accessibilityLabel(String(localized: "Subscribing"))
                        } else {
                            Text("Confirm Subscribe")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSubscribing || store.isLoading || parsed == nil || request.feedUrl.isEmpty)
                    .accessibilityHint(String(localized: "Adds this podcast to your library after preview"))
                }

                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .frame(maxWidth: .infinity)
            }

            if let error = store.lastError, !isAlreadySubscribed {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Preview")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openFeed) { feed in
            FeedDetailView(feed: feed)
        }
        .task {
            await loadPreview()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            artwork
            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .font(.title3.weight(.semibold))
                    .lineLimit(3)
                if let author = displayAuthor {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let language = parsed?.displayLanguage {
                    Text(language)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityLabel(String(localized: "Language \(language)"))
                }
                if let medium = parsed?.displayMedium {
                    Text(medium)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2), in: Capsule())
                        .accessibilityLabel(String(localized: "Medium \(medium)"))
                }
                if let itunesType = parsed?.displayItunesType {
                    Text(itunesType)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2), in: Capsule())
                        .accessibilityLabel(parsed?.itunesTypeAccessibilityLabel ?? itunesType)
                }
                if let uf = parsed?.displayUpdateFrequency {
                    FeedUpdateFrequencyCapsule(frequency: uf, compact: true)
                }
                if parsed?.isItunesComplete == true {
                    Text(String(localized: "Complete"))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2), in: Capsule())
                        .accessibilityLabel(parsed?.itunesCompleteAccessibilityLabel ?? String(localized: "Complete"))
                }
                if let cats = parsed?.categoriesCaption {
                    Text(cats)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .accessibilityLabel(String(localized: "Categories \(cats)"))
                }
                if parsed?.isExplicit == true {
                    Text(String(localized: "Explicit"))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2), in: Capsule())
                        .accessibilityLabel(String(localized: "Explicit"))
                }
                Text(request.feedUrl)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                if isAlreadySubscribed {
                    Text("Already subscribed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(String(localized: "Already subscribed"))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var artwork: some View {
        let size: CGFloat = 88
        if let url = displayArtworkURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    placeholder
                case .empty:
                    ProgressView()
                @unknown default:
                    placeholder
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            placeholder
                .frame(width: size, height: size)
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.quaternary)
            .overlay {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
    }

    @MainActor
    private func loadPreview() async {
        let resolved: String
        switch FeedURLNormalization.normalize(request.feedUrl) {
        case .ok(let url):
            resolved = url
        case .empty, .invalid:
            loadError = String(localized: "Enter a valid http(s) feed URL")
            return
        }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let feed = try await repository.fetchAndParse(feedUrl: resolved)
            parsed = feed
        } catch is CancellationError {
            // ignore
        } catch {
            parsed = nil
            loadError = error.localizedDescription
        }
    }

    @MainActor
    private func confirmSubscribe() async {
        guard !isAlreadySubscribed else { return }
        let resolved: String
        switch FeedURLNormalization.normalize(request.feedUrl) {
        case .ok(let url):
            resolved = url
        case .empty, .invalid:
            return
        }
        // Extra guard: library may match via canonical key even if raw strings differ.
        if FeedURLNormalization.subscribedFeed(matching: resolved, in: store.feeds) != nil {
            return
        }
        isSubscribing = true
        defer { isSubscribing = false }
        await store.subscribe(feedUrl: resolved)
        if store.lastError == nil {
            onSubscribed?()
            dismiss()
        }
    }

    private static func shortDate(_ epochMs: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(epochMs) / 1000)
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
