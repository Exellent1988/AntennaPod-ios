import SwiftUI
import UIKit

/// Scrollable podcast / feed description sheet (plain text; HTML stripped for beta).
/// Parallel to `EpisodeDescriptionSheetView` shownotes. Uses `PodcastFeed.descriptionText` only —
/// no author field on the model in this beta.
/// Supports `.searchable` filter over already-loaded plain paragraphs/lines (case-insensitive,
/// ~250 ms debounce). Does not fetch remote HTML beyond the feed's description field —
/// no WebView / rich HTML renderer.
struct FeedDescriptionSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let feed: PodcastFeed

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?

    @State private var showCopiedAlert = false
    @State private var copiedAlertMessage = ""
    @State private var copyFeedbackTick = 0

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    private var plainDescription: String {
        guard let raw = feed.descriptionText else { return "" }
        return HTMLTextStripping.plainText(from: raw)
    }

    private var hasPlainDescription: Bool {
        !plainDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Paragraphs (blank-line split) or non-empty lines when the text is a single block.
    private var paragraphs: [String] {
        let trimmed = plainDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let blankSplit = trimmed
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if blankSplit.count > 1 { return blankSplit }
        let lineSplit = trimmed
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lineSplit.isEmpty ? [trimmed] : lineSplit
    }

    /// Visible paragraphs after light-debounced case-insensitive filter.
    private var filteredParagraphs: [String] {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return paragraphs }
        return paragraphs.filter { $0.localizedCaseInsensitiveContains(q) }
    }

    private var isFiltering: Bool {
        !debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var websiteURL: URL? {
        feed.websiteURL
    }

    var body: some View {
        NavigationStack {
            Group {
                if plainDescription.isEmpty {
                    ContentUnavailableView(
                        "No description",
                        systemImage: "info.circle",
                        description: Text("This podcast has no description in the feed.")
                    )
                } else {
                    descriptionContent
                        .searchable(text: $searchText, prompt: "Search description")
                        .onChange(of: searchText) { _, newValue in
                            scheduleFilter(for: newValue)
                        }
                }
            }
            .navigationTitle("Description")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        copyPodcastDescription()
                    } label: {
                        Image(systemName: "doc.plaintext")
                    }
                    .disabled(!hasPlainDescription)
                    .accessibilityLabel(String(localized: "Copy podcast description"))
                    .accessibilityHint(String(localized: "Copies the podcast description to the pasteboard"))

                    if let url = websiteURL {
                        Button {
                            openURL(url)
                        } label: {
                            Image(systemName: "safari")
                        }
                        .accessibilityLabel(String(localized: "Open podcast website"))
                        .accessibilityHint(String(localized: "Opens the podcast webpage in the system browser"))
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Plain text — HTML tags stripped")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.bar)
            }
            .alert(
                String(localized: "Copied"),
                isPresented: $showCopiedAlert
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(copiedAlertMessage)
            }
            .sensoryFeedback(.success, trigger: copyFeedbackTick)
        }
        .onDisappear {
            debounceTask?.cancel()
        }
    }

    @ViewBuilder
    private var descriptionContent: some View {
        if isFiltering && filteredParagraphs.isEmpty {
            ContentUnavailableView(
                "No matching text",
                systemImage: "magnifyingglass",
                description: Text("No description text matches your search.")
            )
        } else if isFiltering {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Text(feed.title)
                        .font(.title2.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(Array(filteredParagraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .accessibilityLabel(paragraph)
                    }
                }
                .padding()
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(feed.title)
                        .font(.title2.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)

                    Text(plainDescription)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding()
            }
        }
    }

    private func copyPodcastDescription() {
        let text = plainDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        copiedAlertMessage = String(localized: "Podcast description copied to the pasteboard.")
        copyFeedbackTick += 1
        showCopiedAlert = true
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
