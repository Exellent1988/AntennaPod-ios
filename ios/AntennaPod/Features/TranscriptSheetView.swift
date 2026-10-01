import SwiftUI

/// Scrollable transcript sheet opened from the full player when the feed provides a URL.
/// Cue list supports `.searchable` filter over already-loaded cue text (case-insensitive,
/// ~250 ms debounce). Does not fetch or generate transcripts; feed URL only — no STT.
struct TranscriptSheetView: View {
    @EnvironmentObject private var playback: PlaybackService
    @Environment(\.dismiss) private var dismiss

    let episode: PodcastEpisode

    @State private var transcript: ParsedTranscript?
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    private var cues: [TranscriptCue] { transcript?.cues ?? [] }

    /// Visible cues after light-debounced case-insensitive filter on cue text (+ speaker when set).
    private var filteredCues: [TranscriptCue] {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return cues }
        return cues.filter { cue in
            if cue.text.localizedCaseInsensitiveContains(q) { return true }
            if let speaker = cue.speaker, speaker.localizedCaseInsensitiveContains(q) { return true }
            return false
        }
    }

    private var currentCueIndex: Int? {
        TranscriptCueIndexing.currentIndex(in: cues, at: playback.positionSeconds)
    }

    private var currentCueId: String? {
        guard let index = currentCueIndex, cues.indices.contains(index) else { return nil }
        return cues[index].id
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && transcript == nil {
                    ProgressView("Loading transcript…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage, transcript == nil {
                    ContentUnavailableView(
                        "Transcript unavailable",
                        systemImage: "text.bubble",
                        description: Text(errorMessage)
                    )
                } else if let transcript, !transcript.isEmpty {
                    content(transcript)
                } else {
                    ContentUnavailableView(
                        "No transcript text",
                        systemImage: "text.bubble",
                        description: Text("The feed URL returned empty or unreadable content.")
                    )
                }
            }
            .navigationTitle("Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("From feed URL only — no speech-to-text")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.bar)
            }
        }
        .task(id: episode.transcriptUrl) {
            await load()
        }
        .onDisappear {
            debounceTask?.cancel()
        }
    }

    @ViewBuilder
    private func content(_ transcript: ParsedTranscript) -> some View {
        if transcript.hasSeekableCues {
            cueList
                .searchable(text: $searchText, prompt: "Search transcript")
                .onChange(of: searchText) { _, newValue in
                    scheduleFilter(for: newValue)
                }
        } else if let plain = transcript.plainText, !plain.isEmpty {
            ScrollView {
                Text(plain)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var cueList: some View {
        if cues.isEmpty {
            ContentUnavailableView(
                "No transcript text",
                systemImage: "text.bubble",
                description: Text("The feed URL returned empty or unreadable content.")
            )
        } else if filteredCues.isEmpty {
            ContentUnavailableView(
                "No matching cues",
                systemImage: "magnifyingglass",
                description: Text("No cues match your search.")
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(filteredCues) { cue in
                            let isCurrent = cue.id == currentCueId
                            Button {
                                playback.seek(toSeconds: cue.startTimeSeconds)
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Text(format(cue.startTimeSeconds))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(minWidth: 44, alignment: .trailing)
                                    VStack(alignment: .leading, spacing: 2) {
                                        if let speaker = cue.speaker, !speaker.isEmpty {
                                            Text(speaker)
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(cue.text)
                                            .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                                            .foregroundStyle(isCurrent ? .primary : .secondary)
                                            .multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                .background {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(isCurrent ? Color.accentColor.opacity(0.12) : Color.clear)
                                }
                            }
                            .buttonStyle(.plain)
                            .id(cue.id)
                            .accessibilityLabel(
                                "\(cue.speaker.map { $0 + ", " } ?? "")\(cue.text), \(format(cue.startTimeSeconds))"
                            )
                            .accessibilityHint(String(localized: "Seeks playback to this time"))
                            .accessibilityAddTraits(isCurrent ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .onChange(of: currentCueId) { _, newId in
                    guard let newId,
                          filteredCues.contains(where: { $0.id == newId }) else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(newId, anchor: .center)
                    }
                }
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

    @MainActor
    private func load() async {
        guard let url = episode.transcriptUrl, !url.isEmpty else {
            errorMessage = String(localized: "No transcript URL on this episode.")
            return
        }
        if let cached = TranscriptService.cached(forURL: url) {
            transcript = cached
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            transcript = try await TranscriptService.fetch(
                urlString: url,
                mimeHint: episode.transcriptType
            )
        } catch {
            errorMessage = error.localizedDescription
            transcript = nil
        }
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
