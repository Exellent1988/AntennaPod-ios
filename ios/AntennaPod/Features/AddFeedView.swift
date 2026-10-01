import SwiftUI

/// Add podcast: Apple Podcasts / Podcast Index search + subscribe-by-URL.
struct AddFeedView: View {
    @EnvironmentObject private var store: PodcastStore
    @Environment(\.dismiss) private var dismiss

    @State private var mode: AddMode = .apple
    @State private var urlText = "https://"
    @FocusState private var urlFocused: Bool

    // Apple Podcasts search
    @State private var appleSearchText = ""
    @State private var appleResults: [ItunesPodcastResult] = []
    @State private var appleIsSearching = false
    @State private var appleSearchError: String?
    @State private var appleDidSearch = false
    @State private var appleSearchTask: Task<Void, Never>?

    // Podcast Index search
    @State private var indexSearchText = ""
    @State private var indexResults: [PodcastIndexPodcastResult] = []
    @State private var indexIsSearching = false
    @State private var indexSearchError: String?
    @State private var indexDidSearch = false
    @State private var indexSearchTask: Task<Void, Never>?
    @State private var indexHasKeys = PodcastIndexKeychain.hasCredentials

    @State private var subscribingFeedUrl: String?

    private let itunesSearcher = ItunesSearchService()
    private let podcastIndexSearcher = PodcastIndexSearchService()
    private let debounceNs: UInt64 = 400_000_000 // 400 ms

    private enum AddMode: String, CaseIterable, Identifiable {
        case apple = "Apple Podcasts"
        case podcastIndex = "Podcast Index"
        case url = "Feed URL"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    ForEach(AddMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                switch mode {
                case .apple:
                    appleSearchContent
                case .podcastIndex:
                    podcastIndexSearchContent
                case .url:
                    urlContent
                }
            }
            .navigationTitle("Add podcast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        appleSearchTask?.cancel()
                        indexSearchTask?.cancel()
                        dismiss()
                    }
                }
                if mode == .url {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Subscribe") {
                            Task { await subscribeURL() }
                        }
                        .disabled(store.isLoading || urlText.trimmingCharacters(in: .whitespacesAndNewlines).count < 8)
                    }
                }
            }
            .onChange(of: appleSearchText) { _, newValue in
                scheduleAppleSearch(for: newValue)
            }
            .onChange(of: indexSearchText) { _, newValue in
                scheduleIndexSearch(for: newValue)
            }
            .onChange(of: mode) { _, newMode in
                if newMode == .podcastIndex {
                    indexHasKeys = PodcastIndexKeychain.hasCredentials
                }
            }
            .onDisappear {
                appleSearchTask?.cancel()
                indexSearchTask?.cancel()
            }
        }
    }

    // MARK: - Search (Apple Podcasts)

    private var appleSearchContent: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search Apple Podcasts", text: $appleSearchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { runAppleSearchImmediately() }
                    if appleIsSearching {
                        ProgressView()
                            .controlSize(.small)
                    } else if !appleSearchText.isEmpty {
                        Button {
                            appleSearchText = ""
                            appleResults = []
                            appleSearchError = nil
                            appleDidSearch = false
                            appleSearchTask?.cancel()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
            }

            if let appleSearchError {
                Section {
                    Text(appleSearchError)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
            }

            if appleDidSearch && !appleIsSearching && appleResults.isEmpty && appleSearchError == nil {
                Section {
                    ContentUnavailableView(
                        "No podcasts found",
                        systemImage: "magnifyingglass",
                        description: Text("Try another name or artist, or switch to Feed URL / Podcast Index.")
                    )
                    .listRowBackground(Color.clear)
                }
            }

            if !appleResults.isEmpty {
                Section("Results") {
                    ForEach(appleResults) { item in
                        DiscoveryResultRow(
                            title: item.title,
                            author: item.author,
                            artworkURL: item.artworkURL,
                            feedUrl: item.feedUrl,
                            isSubscribed: store.feeds.contains { $0.feedUrl == item.feedUrl },
                            isSubscribing: subscribingFeedUrl == item.feedUrl,
                            onSubscribe: {
                                Task { await subscribeFeedUrl(item.feedUrl) }
                            }
                        )
                    }
                }
            }

            if let error = store.lastError, mode == .apple {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Search (Podcast Index)

    private var podcastIndexSearchContent: some View {
        List {
            if !indexHasKeys {
                Section {
                    ContentUnavailableView(
                        "API keys required",
                        systemImage: "key",
                        description: Text(
                            "Podcast Index needs a free API key and secret from podcastindex.org (API docs / register). Paste them under Settings → Discovery. Keys stay in the Keychain — nothing is hardcoded or shipped with the app."
                        )
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search Podcast Index", text: $indexSearchText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .onSubmit { runIndexSearchImmediately() }
                        if indexIsSearching {
                            ProgressView()
                                .controlSize(.small)
                        } else if !indexSearchText.isEmpty {
                            Button {
                                indexSearchText = ""
                                indexResults = []
                                indexSearchError = nil
                                indexDidSearch = false
                                indexSearchTask?.cancel()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear search")
                        }
                    }
                }

                if let indexSearchError {
                    Section {
                        Text(indexSearchError)
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }

                if indexDidSearch && !indexIsSearching && indexResults.isEmpty && indexSearchError == nil {
                    Section {
                        ContentUnavailableView(
                            "No podcasts found",
                            systemImage: "magnifyingglass",
                            description: Text("Try another name or author, or switch to Apple Podcasts / Feed URL.")
                        )
                        .listRowBackground(Color.clear)
                    }
                }

                if !indexResults.isEmpty {
                    Section("Results") {
                        ForEach(indexResults) { item in
                            DiscoveryResultRow(
                                title: item.title,
                                author: item.author,
                                artworkURL: item.artworkURL,
                                feedUrl: item.feedUrl,
                                isSubscribed: store.feeds.contains { $0.feedUrl == item.feedUrl },
                                isSubscribing: subscribingFeedUrl == item.feedUrl,
                                onSubscribe: {
                                    Task { await subscribeFeedUrl(item.feedUrl) }
                                }
                            )
                        }
                    }
                }

                if let error = store.lastError, mode == .podcastIndex {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .onAppear {
            indexHasKeys = PodcastIndexKeychain.hasCredentials
        }
    }

    // MARK: - Feed URL

    private var urlContent: some View {
        Form {
            Section("Feed URL") {
                TextField("https://example.com/feed.xml", text: $urlText)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .focused($urlFocused)
            }
            if let error = store.lastError {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            Section {
                Text("Paste an RSS/Atom podcast feed URL, or use Apple Podcasts / Podcast Index search to find feeds.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if mode == .url {
                urlFocused = true
            }
        }
    }

    // MARK: - Apple search actions

    private func scheduleAppleSearch(for term: String) {
        appleSearchTask?.cancel()
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            appleResults = []
            appleSearchError = nil
            appleDidSearch = false
            appleIsSearching = false
            return
        }
        appleSearchTask = Task {
            try? await Task.sleep(nanoseconds: debounceNs)
            guard !Task.isCancelled else { return }
            await performAppleSearch(term: trimmed)
        }
    }

    private func runAppleSearchImmediately() {
        appleSearchTask?.cancel()
        let trimmed = appleSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appleSearchTask = Task {
            await performAppleSearch(term: trimmed)
        }
    }

    @MainActor
    private func performAppleSearch(term: String) async {
        appleIsSearching = true
        appleSearchError = nil
        defer { appleIsSearching = false }
        do {
            let found = try await itunesSearcher.search(term: term)
            guard !Task.isCancelled else { return }
            appleResults = found
            appleDidSearch = true
        } catch is CancellationError {
            // ignore
        } catch {
            guard !Task.isCancelled else { return }
            appleResults = []
            appleDidSearch = true
            appleSearchError = error.localizedDescription
        }
    }

    // MARK: - Podcast Index search actions

    private func scheduleIndexSearch(for term: String) {
        indexSearchTask?.cancel()
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            indexResults = []
            indexSearchError = nil
            indexDidSearch = false
            indexIsSearching = false
            return
        }
        guard indexHasKeys else { return }
        indexSearchTask = Task {
            try? await Task.sleep(nanoseconds: debounceNs)
            guard !Task.isCancelled else { return }
            await performIndexSearch(term: trimmed)
        }
    }

    private func runIndexSearchImmediately() {
        indexSearchTask?.cancel()
        let trimmed = indexSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, indexHasKeys else { return }
        indexSearchTask = Task {
            await performIndexSearch(term: trimmed)
        }
    }

    @MainActor
    private func performIndexSearch(term: String) async {
        indexIsSearching = true
        indexSearchError = nil
        defer { indexIsSearching = false }
        do {
            let found = try await podcastIndexSearcher.search(term: term)
            guard !Task.isCancelled else { return }
            indexResults = found
            indexDidSearch = true
        } catch is CancellationError {
            // ignore
        } catch {
            guard !Task.isCancelled else { return }
            indexResults = []
            indexDidSearch = true
            indexSearchError = error.localizedDescription
        }
    }

    // MARK: - Subscribe

    @MainActor
    private func subscribeFeedUrl(_ feedUrl: String) async {
        guard !feedUrl.isEmpty else { return }
        subscribingFeedUrl = feedUrl
        defer { subscribingFeedUrl = nil }
        await store.subscribe(feedUrl: feedUrl)
        if store.lastError == nil {
            dismiss()
        }
    }

    @MainActor
    private func subscribeURL() async {
        await store.subscribe(feedUrl: urlText.trimmingCharacters(in: .whitespacesAndNewlines))
        if store.lastError == nil {
            dismiss()
        }
    }
}
