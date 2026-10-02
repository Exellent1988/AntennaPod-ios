import SwiftUI

/// Chapters list sheet mirroring Full player list UX: searchable titles, tap → seek,
/// current highlight, duration / current remaining when end known, optional chapters URL.
///
/// Already-loaded chapters only — does **not** fetch remote Podcast Index JSON or
/// media-file tags (same honesty as mini Previous/Next). Full Player still lazy-loads.
struct EpisodeChaptersSheet: View {
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var store: PodcastStore
    @Environment(\.dismiss) private var dismiss

    /// Chapters already known on the episode / player (PSC / persisted remote / media).
    let chapters: [PodcastChapter]
    /// Prefer store-resolved episode for duration + chapters URL Open/Copy.
    let episode: PodcastEpisode?

    @State private var chapterSearchText = ""
    @State private var chapterDebouncedQuery = ""
    @State private var chapterDebounceTask: Task<Void, Never>?

    private let chapterDebounceNs: UInt64 = 250_000_000 // 250 ms

    private var displayPosition: Double {
        playback.positionSeconds
    }

    private var currentChapterIndex: Int? {
        ChapterIndexing.currentIndex(in: chapters, at: displayPosition)
    }

    /// Visible chapter indices after light-debounced case-insensitive title filter.
    private var filteredChapterIndices: [Int] {
        let q = chapterDebouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return Array(chapters.indices) }
        return chapters.indices.filter { chapters[$0].title.localizedCaseInsensitiveContains(q) }
    }

    private var isFilteringChapters: Bool {
        !chapterDebouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Known episode duration for last-chapter end (live player → feed → saved playback).
    /// `nil` when unknown — last chapter duration/remaining stays hidden (no invented end).
    private var chapterEpisodeDurationSeconds: Double? {
        let live = playback.durationSeconds
        if live.isFinite, live > 0 { return live }
        if let episode, episode.hasKnownDuration {
            return episode.durationSeconds
        }
        if let episode {
            let saved = store.playbackState(for: episode.id).durationSeconds
            if saved.isFinite, saved > 0 { return saved }
        }
        return nil
    }

    private var showChaptersURL: Bool {
        episode?.hasPodcastIndexChapterURL == true
    }

    var body: some View {
        NavigationStack {
            Group {
                if chapters.isEmpty {
                    ContentUnavailableView(
                        "No chapters available",
                        systemImage: "list.bullet",
                        description: Text(String(localized: "No chapters known for this episode yet."))
                    )
                } else if isFilteringChapters && filteredChapterIndices.isEmpty {
                    ContentUnavailableView(
                        "No matching chapters",
                        systemImage: "magnifyingglass",
                        description: Text("No chapters match your search.")
                    )
                    .accessibilityElement(children: .combine)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredChapterIndices, id: \.self) { index in
                                chapterRow(index: index)
                            }
                            if let ep = episode, showChaptersURL {
                                PodcastChaptersURLView(episode: ep, showsSectionTitle: true)
                                    .padding(.top, 12)
                                    .padding(.horizontal, 4)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle(String(localized: "Chapters"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
            .searchable(text: $chapterSearchText, prompt: "Search chapters")
            .onChange(of: chapterSearchText) { _, newValue in
                scheduleChapterFilter(for: newValue)
            }
        }
        .presentationDetents([.medium, .large])
        .onDisappear {
            chapterDebounceTask?.cancel()
        }
    }

    @ViewBuilder
    private func chapterRow(index: Int) -> some View {
        let chapter = chapters[index]
        ChapterListRow(
            startTimeText: format(chapter.startTimeSeconds),
            title: chapter.title,
            imageURL: chapter.displayImageURL,
            trailingTimeLabel: chapterTrailingTimeLabel(index: index),
            isCurrent: index == currentChapterIndex,
            accessibilityBaseLabel: chapterAccessibilityLabel(index: index, chapter: chapter),
            onSeek: {
                playback.seek(toSeconds: chapter.startTimeSeconds)
            }
        )
    }

    /// Trailing time for a chapter row: current → live remaining (−m:ss) when end known;
    /// otherwise chapter duration when known. Hidden when times cannot be derived honestly.
    private func chapterTrailingTimeLabel(index: Int) -> String? {
        let episodeDuration = chapterEpisodeDurationSeconds
        if index == currentChapterIndex,
           let remaining = ChapterIndexing.remainingSeconds(
               in: chapters,
               atIndex: index,
               positionSeconds: displayPosition,
               episodeDurationSeconds: episodeDuration
           ) {
            return formatRemaining(remaining)
        }
        if let duration = ChapterIndexing.durationSeconds(
            in: chapters,
            atIndex: index,
            episodeDurationSeconds: episodeDuration
        ) {
            return format(duration)
        }
        return nil
    }

    private func chapterAccessibilityLabel(index: Int, chapter: PodcastChapter) -> String {
        var parts = [String(localized: "Chapter \(chapter.title), \(format(chapter.startTimeSeconds))")]
        let episodeDuration = chapterEpisodeDurationSeconds
        if index == currentChapterIndex,
           let remaining = ChapterIndexing.remainingSeconds(
               in: chapters,
               atIndex: index,
               positionSeconds: displayPosition,
               episodeDurationSeconds: episodeDuration
           ) {
            parts.append(String(localized: "\(format(remaining)) remaining"))
        } else if let duration = ChapterIndexing.durationSeconds(
            in: chapters,
            atIndex: index,
            episodeDurationSeconds: episodeDuration
        ) {
            parts.append(String(localized: "Duration \(format(duration))"))
        }
        return parts.joined(separator: ", ")
    }

    private func scheduleChapterFilter(for term: String) {
        chapterDebounceTask?.cancel()
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            chapterDebouncedQuery = ""
            return
        }
        chapterDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: chapterDebounceNs)
            guard !Task.isCancelled else { return }
            chapterDebouncedQuery = trimmed
        }
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else {
            return "--:--"
        }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// Remaining time with a leading minus (−m:ss or −h:mm:ss).
    private func formatRemaining(_ seconds: Double) -> String {
        guard seconds.isFinite else {
            return "--:--"
        }
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "-%d:%02d:%02d", h, m, s)
        }
        return String(format: "-%d:%02d", m, s)
    }
}
