import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Add podcast: Apple Podcasts / Podcast Index / fyyd search + preview-by-URL (confirm subscribe) + Add from Clipboard.
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

    // fyyd search
    @State private var fyydSearchText = ""
    @State private var fyydResults: [FyydPodcastResult] = []
    @State private var fyydIsSearching = false
    @State private var fyydSearchError: String?
    @State private var fyydDidSearch = false
    @State private var fyydSearchTask: Task<Void, Never>?

    @State private var previewRequest: FeedPreviewRequest?
    /// Trimmed http(s) URL from the pasteboard when it looks plausible; nil hides the action.
    @State private var clipboardFeedURL: String?
    @Environment(\.scenePhase) private var scenePhase

    // Local folder
    @State private var showFolderPicker = false
    @State private var folderError: String?
    @State private var folderStatus: String?
    @State private var isAddingFolder = false

    private let itunesSearcher = ItunesSearchService()
    private let podcastIndexSearcher = PodcastIndexSearchService()
    private let fyydSearcher = FyydSearchService()
    private let debounceNs: UInt64 = 400_000_000 // 400 ms

    private enum AddMode: String, CaseIterable, Identifiable {
        case apple
        case podcastIndex
        case fyyd
        case url
        case folder
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .apple: "Apple"
            case .podcastIndex: "Index"
            case .fyyd: "fyyd"
            case .url: "URL"
            case .folder: "Folder"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    ForEach(AddMode.allCases) { m in
                        Text(m.title).tag(m)
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
                case .fyyd:
                    fyydSearchContent
                case .url:
                    urlContent
                case .folder:
                    folderContent
                }
            }
            .navigationTitle("Add podcast")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $previewRequest) { request in
                FeedPreviewView(request: request) {
                    dismiss()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        appleSearchTask?.cancel()
                        indexSearchTask?.cancel()
                        fyydSearchTask?.cancel()
                        dismiss()
                    }
                }
                if let clipboardFeedURL {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            addFromClipboard(clipboardFeedURL)
                        } label: {
                            Label("Add from Clipboard", systemImage: "doc.on.clipboard")
                        }
                        .accessibilityLabel(String(localized: "Add from Clipboard"))
                        .accessibilityHint(String(localized: "Opens a preview for the feed URL on the pasteboard"))
                    }
                }
                if mode == .url {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Preview") {
                            openURLPreview()
                        }
                        .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).count < 8)
                    }
                }
            }
            .onChange(of: appleSearchText) { _, newValue in
                scheduleAppleSearch(for: newValue)
            }
            .onChange(of: indexSearchText) { _, newValue in
                scheduleIndexSearch(for: newValue)
            }
            .onChange(of: fyydSearchText) { _, newValue in
                scheduleFyydSearch(for: newValue)
            }
            .onChange(of: mode) { _, newMode in
                if newMode == .podcastIndex {
                    indexHasKeys = PodcastIndexKeychain.hasCredentials
                }
                refreshClipboardFeedURL()
            }
            .onDisappear {
                appleSearchTask?.cancel()
                indexSearchTask?.cancel()
                fyydSearchTask?.cancel()
            }
            .onAppear {
                refreshClipboardFeedURL()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    refreshClipboardFeedURL()
                }
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
                        .accessibilityLabel(String(localized: "Clear search"))
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
                        description: Text("Try another name or artist, or switch to Index / fyyd / URL.")
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
                            .accessibilityLabel(String(localized: "Clear search"))
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
                            description: Text("Try another name or author, or switch to Apple / fyyd / URL.")
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
            if let clipboardFeedURL {
                Section {
                    Button {
                        addFromClipboard(clipboardFeedURL)
                    } label: {
                        Label("Add from Clipboard", systemImage: "doc.on.clipboard")
                    }
                    .accessibilityHint(String(localized: "Opens a preview for the feed URL on the pasteboard"))
                    Text(clipboardFeedURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .accessibilityLabel(String(localized: "Clipboard feed URL"))
                } footer: {
                    Text("Uses the http(s) URL currently on the pasteboard. Opens Preview — does not subscribe until you confirm.")
                }
            }
            Section {
                Button("Preview feed") {
                    openURLPreview()
                }
                .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).count < 8)
            }
            Section {
                Text("Paste an RSS/Atom podcast feed URL, or use Apple / Index / fyyd search. Preview fetches the feed before you confirm subscribe. When the pasteboard holds an http(s) URL, use Add from Clipboard.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            refreshClipboardFeedURL()
            if mode == .url {
                urlFocused = true
            }
        }
    }

    // MARK: - Local folder

    private var folderContent: some View {
        List {
            Section {
                Button {
                    folderError = nil
                    folderStatus = nil
                    showFolderPicker = true
                } label: {
                    Label("Choose folder…", systemImage: "folder.badge.plus")
                }
                .disabled(isAddingFolder)

                if isAddingFolder {
                    ProgressView("Scanning folder…")
                }
                if let folderStatus {
                    Text(folderStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let folderError {
                    Text(folderError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Local folder feed")
            } footer: {
                Text("Beta: pick a folder of audio files (mp3, m4a, aac, wav, flac). Creates a synthetic subscription — no RSS, no network refresh. Access is kept via a security-scoped bookmark; unsubscribe releases it. Refresh re-scans the folder.")
            }
        }
        .listStyle(.insetGrouped)
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFolderPick(result)
        }
    }

    private func handleFolderPick(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            folderError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            isAddingFolder = true
            folderError = nil
            folderStatus = nil
            defer { isAddingFolder = false }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                try store.subscribeLocalFolder(folderURL: url)
                folderStatus = "Added “\(url.lastPathComponent)” as a local folder feed."
                dismiss()
            } catch {
                folderError = error.localizedDescription
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

    // MARK: - Search (fyyd)

    private var fyydSearchContent: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search fyyd", text: $fyydSearchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { runFyydSearchImmediately() }
                    if fyydIsSearching {
                        ProgressView()
                            .controlSize(.small)
                    } else if !fyydSearchText.isEmpty {
                        Button {
                            fyydSearchText = ""
                            fyydResults = []
                            fyydSearchError = nil
                            fyydDidSearch = false
                            fyydSearchTask?.cancel()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Clear search"))
                    }
                }
            }

            Section {
                Text("fyyd.de podcast directory — no API key required.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let fyydSearchError {
                Section {
                    Text(fyydSearchError)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
            }

            if fyydDidSearch && !fyydIsSearching && fyydResults.isEmpty && fyydSearchError == nil {
                Section {
                    ContentUnavailableView(
                        "No podcasts found",
                        systemImage: "magnifyingglass",
                        description: Text("Try another name or author, or switch to Apple / Index / URL.")
                    )
                    .listRowBackground(Color.clear)
                }
            }

            if !fyydResults.isEmpty {
                Section("Results") {
                    ForEach(fyydResults) { item in
                        DiscoveryResultRow(
                            title: item.title,
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
    }

    // MARK: - fyyd search actions

    private func scheduleFyydSearch(for term: String) {
        fyydSearchTask?.cancel()
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            fyydResults = []
            fyydSearchError = nil
            fyydDidSearch = false
            fyydIsSearching = false
            return
        }
        fyydSearchTask = Task {
            try? await Task.sleep(nanoseconds: debounceNs)
            guard !Task.isCancelled else { return }
            await performFyydSearch(term: trimmed)
        }
    }

    private func runFyydSearchImmediately() {
        fyydSearchTask?.cancel()
        let trimmed = fyydSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        fyydSearchTask = Task {
            await performFyydSearch(term: trimmed)
        }
    }

    @MainActor
    private func performFyydSearch(term: String) async {
        fyydIsSearching = true
        fyydSearchError = nil
        defer { fyydIsSearching = false }
        do {
            let found = try await fyydSearcher.search(term: term)
            guard !Task.isCancelled else { return }
            fyydResults = found
            fyydDidSearch = true
        } catch is CancellationError {
            // ignore
        } catch {
            guard !Task.isCancelled else { return }
            fyydResults = []
            fyydDidSearch = true
            fyydSearchError = error.localizedDescription
        }
    }

    // MARK: - Clipboard

    /// Refresh pasteboard detection. Only http/https with a host; trimmed; first line only.
    /// Does **not** auto-subscribe — the action stays user-initiated.
    private func refreshClipboardFeedURL() {
        clipboardFeedURL = Self.plausibleFeedURL(from: UIPasteboard.general.string)
    }

    /// True when the string looks like a network feed URL the existing Preview path can try.
    static func plausibleFeedURL(from pasteboardString: String?) -> String? {
        guard let raw = pasteboardString else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let firstLine = trimmed
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? trimmed
        guard let url = URL(string: firstLine),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty
        else {
            return nil
        }
        return firstLine
    }

    /// Fill the URL field and open the same Preview → Confirm Subscribe path as manual URL entry.
    private func addFromClipboard(_ feedURL: String) {
        let trimmed = feedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.plausibleFeedURL(from: trimmed) != nil else {
            refreshClipboardFeedURL()
            return
        }
        mode = .url
        urlText = trimmed
        previewRequest = FeedPreviewRequest(feedUrl: trimmed)
    }

    // MARK: - Preview

    private func openURLPreview() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else { return }
        previewRequest = FeedPreviewRequest(feedUrl: trimmed)
    }
}
