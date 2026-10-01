import SwiftUI
import UIKit

/// Scrollable episode shownotes / description sheet (plain text; HTML stripped for beta).
/// Supports `.searchable` filter over already-loaded plain paragraphs/lines (case-insensitive,
/// ~250 ms debounce). Does not fetch remote HTML beyond the episode's feed description —
/// no WebView / rich HTML renderer.
struct EpisodeDescriptionSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var playback: PlaybackService

    let episode: PodcastEpisode
    /// Optional podcast name for share message (`Title — Podcast`). When empty, looked up from the store.
    var feedTitle: String? = nil

    @State private var showCopiedAlert = false
    @State private var copiedAlertMessage = ""
    @State private var copyURLFeedbackTick = 0

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    private var plainDescription: String {
        guard let raw = episode.descriptionText else { return "" }
        return HTMLTextStripping.plainText(from: raw)
    }

    private var hasPlainShownotes: Bool {
        !plainDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Item podcast:person when the feed provided them — empty → hide (never invent).
    private var displayPeople: [PodcastPerson] {
        episode.displayPeople
    }

    private var hasPeople: Bool {
        !displayPeople.isEmpty
    }

    /// Item podcast:location when the feed provided them — empty → hide (never invent / never geocode).
    private var displayLocations: [PodcastLocation] {
        episode.displayLocations
    }

    private var hasLocations: Bool {
        !displayLocations.isEmpty
    }

    /// Item podcast:socialInteract when the feed provided openable http(s) — empty → hide (never invent).
    private var displaySocialInteracts: [PodcastSocialInteract] {
        episode.displaySocialInteracts
    }

    private var hasSocialInteracts: Bool {
        !displaySocialInteracts.isEmpty
    }

    /// Item podcast:value when the feed provided recipients — empty → hide (display-only; no payments).
    private var displayValues: [PodcastValue] {
        episode.values
    }

    private var hasValues: Bool {
        !episode.displayValueRecipients.isEmpty
    }

    /// Item podcast:alternateEnclosure when the feed provided options — empty → hide (display-only; no player switch).
    private var displayAlternateEnclosures: [PodcastAlternateEnclosure] {
        episode.alternateEnclosures
    }

    private var hasAlternateEnclosures: Bool {
        !episode.displayAlternateEnclosures.isEmpty
    }

    /// Item podcast:soundbite when the feed provided clips — empty → hide (seek when current / else Copy; no clip player).
    private var displaySoundbites: [PodcastSoundbite] {
        episode.soundbites
    }

    private var hasSoundbites: Bool {
        !episode.displaySoundbites.isEmpty
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

    private var resolvedFeed: PodcastFeed? {
        store.feed(containingEpisodeId: episode.id)
    }

    private var resolvedFeedTitle: String {
        if let feedTitle, !feedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return feedTitle
        }
        return resolvedFeed?.title ?? ""
    }

    private var shareURL: URL? {
        episode.shareURL(feed: resolvedFeed)
    }

    private var shareMessage: String {
        episode.shareMessage(feedTitle: resolvedFeedTitle)
    }

    /// Only when this shownotes episode is the current playback item and position is known.
    private var canShareWithPosition: Bool {
        playback.currentEpisode?.id == episode.id
            && PodcastEpisode.canShareWithPosition(playback.positionSeconds)
    }

    private var shareMessageWithPosition: String {
        episode.shareMessage(
            feedTitle: resolvedFeedTitle,
            positionSeconds: playback.positionSeconds
        )
    }

    private var websiteURL: URL? {
        episode.websiteURL
    }

    var body: some View {
        NavigationStack {
            Group {
                if plainDescription.isEmpty && !hasPeople && !hasLocations && !hasSocialInteracts && !hasValues && !hasAlternateEnclosures && !hasSoundbites {
                    ContentUnavailableView(
                        "No description",
                        systemImage: "doc.text",
                        description: Text("This episode has no shownotes in the feed.")
                    )
                } else if plainDescription.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if hasPeople {
                                PodcastPeopleListView(people: displayPeople)
                            }
                            if hasLocations {
                                PodcastLocationsListView(locations: displayLocations)
                            }
                            if hasSocialInteracts {
                                PodcastSocialInteractListView(socialInteracts: displaySocialInteracts)
                            }
                            if hasValues {
                                PodcastValueRecipientsListView(values: displayValues)
                            }
                            if hasAlternateEnclosures {
                                PodcastAlternateEnclosuresListView(alternateEnclosures: displayAlternateEnclosures)
                            }
                            if hasSoundbites {
                                PodcastSoundbitesListView(soundbites: displaySoundbites, episodeId: episode.id)
                            }
                        }
                        .padding()
                    }
                } else {
                    shownotesContent
                        .searchable(text: $searchText, prompt: "Search shownotes")
                        .onChange(of: searchText) { _, newValue in
                            scheduleFilter(for: newValue)
                        }
                }
            }
            .navigationTitle("Shownotes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        copyShownotes()
                    } label: {
                        Image(systemName: "doc.plaintext")
                    }
                    .disabled(!hasPlainShownotes)
                    .accessibilityLabel(String(localized: "Copy shownotes"))
                    .accessibilityHint(String(localized: "Copies the episode shownotes to the pasteboard"))

                    if let url = websiteURL {
                        Button {
                            openURL(url)
                        } label: {
                            Image(systemName: "safari")
                        }
                        .accessibilityLabel(String(localized: "Open episode website"))
                        .accessibilityHint(String(localized: "Opens the episode webpage in the system browser"))

                        Button {
                            copyEpisodeLink(url)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .accessibilityLabel(String(localized: "Copy episode link"))
                        .accessibilityHint(String(localized: "Copies the episode webpage URL to the pasteboard"))
                    }
                    if let url = episode.mediaURL {
                        Button {
                            copyMediaURL(url)
                        } label: {
                            Image(systemName: "link")
                        }
                        .accessibilityLabel(String(localized: "Copy media URL"))
                        .accessibilityHint(String(localized: "Copies the episode media / enclosure URL to the pasteboard"))
                    }
                    if let url = shareURL {
                        ShareLink(
                            item: url,
                            subject: Text(episode.title),
                            message: Text(shareMessage)
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(String(localized: "Share episode"))
                        .accessibilityHint(String(localized: "Opens the system share sheet with the episode title and link"))

                        if canShareWithPosition {
                            ShareLink(
                                item: url,
                                subject: Text(episode.title),
                                message: Text(shareMessageWithPosition)
                            ) {
                                Image(systemName: "square.and.arrow.up.on.square")
                            }
                            .accessibilityLabel(String(localized: "Share with position"))
                            .accessibilityHint(
                                String(localized: "Opens the system share sheet with the episode title, link, and current playback position")
                            )
                        }
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
            .sensoryFeedback(.success, trigger: copyURLFeedbackTick)
        }
        .onDisappear {
            debounceTask?.cancel()
        }
    }

    @ViewBuilder
    private var shownotesContent: some View {
        if isFiltering && filteredParagraphs.isEmpty {
            ContentUnavailableView(
                "No matching text",
                systemImage: "magnifyingglass",
                description: Text("No shownotes text matches your search.")
            )
        } else if isFiltering {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if hasPeople {
                        PodcastPeopleListView(people: displayPeople)
                    }
                    if hasLocations {
                        PodcastLocationsListView(locations: displayLocations)
                    }
                    if hasSocialInteracts {
                        PodcastSocialInteractListView(socialInteracts: displaySocialInteracts)
                    }
                    if hasValues {
                        PodcastValueRecipientsListView(values: displayValues)
                    }
                    if hasAlternateEnclosures {
                        PodcastAlternateEnclosuresListView(alternateEnclosures: displayAlternateEnclosures)
                    }
                    if hasSoundbites {
                        PodcastSoundbitesListView(soundbites: displaySoundbites, episodeId: episode.id)
                    }
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
                VStack(alignment: .leading, spacing: 16) {
                    if hasPeople {
                        PodcastPeopleListView(people: displayPeople)
                    }
                    if hasLocations {
                        PodcastLocationsListView(locations: displayLocations)
                    }
                    if hasSocialInteracts {
                        PodcastSocialInteractListView(socialInteracts: displaySocialInteracts)
                    }
                    if hasValues {
                        PodcastValueRecipientsListView(values: displayValues)
                    }
                    if hasAlternateEnclosures {
                        PodcastAlternateEnclosuresListView(alternateEnclosures: displayAlternateEnclosures)
                    }
                    if hasSoundbites {
                        PodcastSoundbitesListView(soundbites: displaySoundbites, episodeId: episode.id)
                    }
                    Text(plainDescription)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding()
            }
        }
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

    private func copyShownotes() {
        let text = plainDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        copiedAlertMessage = String(localized: "Shownotes copied to the pasteboard.")
        copyURLFeedbackTick += 1
        showCopiedAlert = true
    }

    private func copyEpisodeLink(_ url: URL) {
        UIPasteboard.general.string = url.absoluteString
        copiedAlertMessage = String(localized: "Episode link copied to the pasteboard.")
        copyURLFeedbackTick += 1
        showCopiedAlert = true
    }

    private func copyMediaURL(_ url: URL) {
        UIPasteboard.general.string = url.absoluteString
        copiedAlertMessage = String(localized: "Media URL copied to the pasteboard.")
        copyURLFeedbackTick += 1
        showCopiedAlert = true
    }
}
