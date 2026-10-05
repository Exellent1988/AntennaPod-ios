import SwiftUI
import UIKit

/// Scrollable transcript sheet opened from the full player when the feed provides a URL.
/// Cue list supports `.searchable` filter over already-loaded cue text (case-insensitive,
/// ~250 ms debounce). Toolbar **Copy transcript** joins already-loaded cues (or plain-text
/// fallback) to the pasteboard — full loaded text, not the search-filtered subset.
/// Toolbar **Copy current cue** copies the cue at `playback.positionSeconds` (same
/// `TranscriptCueIndexing` as highlight / auto-scroll) as one line `m:ss`/`h:mm:ss` +
/// optional `Speaker: ` + text — from the **full** loaded array (ignores search filter).
/// Toolbar **Share current cue** shares that same one-line cue via the system share sheet
/// (`ShareLink`; episode title + cue line when title available) — same disable gate as Copy.
/// Toolbar **Share transcript** offers the same full loaded plain text (episode title + body)
/// via the system share sheet (`ShareLink`) — no fake social / no extra fetch.
/// Toolbar **Copy transcript URL** copies the trimmed non-empty feed URL raw string, while
/// **Share transcript URL** prefers an http(s) URL and preserves the raw fallback.
/// Does not fetch or generate transcripts; feed URL only — no STT.
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

    @State private var showCopiedAlert = false
    @State private var copiedAlertMessage = ""
    @State private var copyFeedbackTick = 0

    private let debounceNs: UInt64 = 250_000_000 // 250 ms

    private var cues: [TranscriptCue] { transcript?.cues ?? [] }

    /// Plain text for pasteboard / share: **full** already-loaded cues (speaker prefixes when set),
    /// else plain-text fallback. Ignores the search filter so Copy / Share always export the whole load.
    private var transcriptPlainForCopy: String {
        if !cues.isEmpty {
            return cues.map { cue in
                let text = cue.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if let speaker = cue.speaker?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !speaker.isEmpty {
                    return "\(speaker): \(text)"
                }
                return text
            }.joined(separator: "\n")
        }
        return transcript?.plainText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Enabled only when already-loaded transcript text is available (not loading / error / empty).
    private var canCopyTranscript: Bool {
        !transcriptPlainForCopy.isEmpty
    }

    /// Same gate as Copy — Share only when already-loaded text exists.
    private var canShareTranscript: Bool { canCopyTranscript }

    private var transcriptURLString: String? {
        guard let raw = episode.transcriptUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return raw
    }

    private var transcriptURL: URL? {
        guard let raw = transcriptURLString,
              let url = URL(string: raw) else {
            return nil
        }
        return url
    }

    private var canCopyOrShareTranscriptURL: Bool {
        transcriptURLString != nil
    }

    private var transcriptURLShareMessage: String {
        String(localized: "Remote transcript URL from the feed.")
    }

    /// System share sheet payload: episode title + full loaded transcript body (same join as Copy).
    private var transcriptShareText: String {
        let body = transcriptPlainForCopy
        guard !body.isEmpty else { return "" }
        let title = episode.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return body }
        return "\(title)\n\n\(body)"
    }

    /// One-line pasteboard text for the cue active at playback position (full loaded array).
    /// Format: `m:ss` / `h:mm:ss` start + optional `Speaker: ` + cue text (same speaker join as full Copy).
    private var currentCuePlainForCopy: String? {
        guard let index = currentCueIndex, cues.indices.contains(index) else { return nil }
        let cue = cues[index]
        let text = cue.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let time = format(cue.startTimeSeconds)
        if let speaker = cue.speaker?.trimmingCharacters(in: .whitespacesAndNewlines),
           !speaker.isEmpty {
            return "\(time) \(speaker): \(text)"
        }
        return "\(time) \(text)"
    }

    /// Enabled when `TranscriptCueIndexing` reports a current cue (nil before first / empty).
    private var canCopyCurrentCue: Bool {
        currentCuePlainForCopy != nil
    }

    /// Same gate as Copy current cue — Share only when a current timed cue exists.
    private var canShareCurrentCue: Bool { canCopyCurrentCue }

    /// System share sheet payload: episode title + one-line current cue (same format as Copy),
    /// or the cue line alone when the episode title is empty.
    private var currentCueShareText: String {
        guard let line = currentCuePlainForCopy, !line.isEmpty else { return "" }
        let title = episode.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return line }
        return "\(title)\n\n\(line)"
    }

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
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(String(localized: "Loading transcript…"))
                        .accessibilityAddTraits(.updatesFrequently)
                } else if let errorMessage, transcript == nil {
                    ContentUnavailableView(
                        "Transcript unavailable",
                        systemImage: "text.bubble",
                        description: Text(errorMessage)
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized: "Transcript unavailable"))
                    .accessibilityValue(errorMessage)
                } else if let transcript, !transcript.isEmpty {
                    content(transcript)
                } else {
                    ContentUnavailableView(
                        "No transcript text",
                        systemImage: "text.bubble",
                        description: Text("The feed URL returned empty or unreadable content.")
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized: "No transcript text"))
                    .accessibilityValue(String(localized: "The feed URL returned empty or unreadable content."))
                }
            }
            .navigationTitle("Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        copyTranscript()
                    } label: {
                        Image(systemName: "doc.plaintext")
                    }
                    .disabled(!canCopyTranscript)
                    .accessibilityLabel(String(localized: "Copy transcript"))
                    .accessibilityHint(String(localized: "Copies the transcript to the pasteboard"))

                    Button {
                        copyCurrentCue()
                    } label: {
                        Image(systemName: "text.quote")
                    }
                    .disabled(!canCopyCurrentCue)
                    .accessibilityLabel(String(localized: "Copy current cue"))
                    .accessibilityHint(
                        String(localized: "Copies the current transcript cue to the pasteboard")
                    )

                    ShareLink(
                        item: currentCueShareText,
                        subject: Text(episode.title)
                    ) {
                        Image(systemName: "quote.bubble")
                    }
                    .disabled(!canShareCurrentCue)
                    .accessibilityLabel(String(localized: "Share current cue"))
                    .accessibilityHint(
                        String(localized: "Opens the system share sheet with the episode title and current transcript cue")
                    )

                    ShareLink(
                        item: transcriptShareText,
                        subject: Text(episode.title)
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(!canShareTranscript)
                    .accessibilityLabel(String(localized: "Share transcript"))
                    .accessibilityHint(
                        String(localized: "Opens the system share sheet with the episode title and transcript")
                    )

                    if canCopyOrShareTranscriptURL, let raw = transcriptURLString {
                        Button {
                            copyTranscriptURL(raw)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .accessibilityLabel(String(localized: "Copy transcript URL"))
                        .accessibilityHint(
                            String(
                                localized: "Copies the feed-provided transcript URL to the pasteboard, not the loaded transcript text"
                            )
                        )

                        if let url = transcriptURL {
                            ShareLink(
                                item: url,
                                subject: Text(episode.title),
                                message: Text(transcriptURLShareMessage)
                            ) {
                                Image(systemName: "link")
                            }
                            .disabled(!canCopyOrShareTranscriptURL)
                            .accessibilityLabel(String(localized: "Share transcript URL"))
                            .accessibilityHint(
                                String(localized: "Shares the feed-provided transcript URL, not the loaded transcript text")
                            )
                        } else {
                            ShareLink(
                                item: raw,
                                subject: Text(episode.title),
                                message: Text(transcriptURLShareMessage)
                            ) {
                                Image(systemName: "link")
                            }
                            .disabled(!canCopyOrShareTranscriptURL)
                            .accessibilityLabel(String(localized: "Share transcript URL"))
                            .accessibilityHint(
                                String(localized: "Shares the feed-provided transcript URL, not the loaded transcript text")
                            )
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    if let transcriptLanguage = episode.displayTranscriptLanguage {
                        transcriptLanguageHeader(transcriptLanguage)
                    }
                    if let transcriptType = episode.displayTranscriptType {
                        transcriptTypeHeader(transcriptType)
                    }
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "No transcript text"))
            .accessibilityValue(String(localized: "The feed URL returned empty or unreadable content."))
        } else if filteredCues.isEmpty {
            ContentUnavailableView(
                "No matching cues",
                systemImage: "magnifyingglass",
                description: Text("No cues match your search.")
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "No matching cues"))
            .accessibilityValue(String(localized: "No cues match your search."))
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(filteredCues) { cue in
                            let isCurrent = cue.id == currentCueId
                            Button {
                                playback.jumpToPosition(seconds: cue.startTimeSeconds)
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
                .onAppear {
                    // The cue list is created only after the transcript loads, with the
                    // playback cue already current. onChange does not run for that value,
                    // so the sheet would stay at the top until the next cue boundary.
                    scrollTranscriptCueIntoView(proxy, cueId: currentCueId, afterLayout: true)
                }
                .onChange(of: currentCueId) { _, newId in
                    scrollTranscriptCueIntoView(proxy, cueId: newId, afterLayout: false)
                }
            }
        }
    }

    /// Scroll the current cue into view. Deferred on first appearance so LazyVStack
    /// has mounted the row; immediate when playback crosses a cue boundary.
    private func scrollTranscriptCueIntoView(
        _ proxy: ScrollViewProxy,
        cueId: String?,
        afterLayout: Bool
    ) {
        guard let cueId, filteredCues.contains(where: { $0.id == cueId }) else { return }
        if afterLayout {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(cueId, anchor: .center)
                }
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(cueId, anchor: .center)
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

    @ViewBuilder
    private func transcriptLanguageHeader(_ language: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(String(localized: "Transcript language"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 8)

                Button {
                    copyTranscriptLanguage(language)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel(String(localized: "Copy transcript language"))
                .accessibilityHint(
                    String(localized: "Copies the exact displayed transcript language to the pasteboard")
                )

                ShareLink(item: language) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(String(localized: "Share transcript language"))
                .accessibilityHint(
                    String(localized: "Shares the exact displayed transcript language as plain text")
                )
            }

            Text(language)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(2)
                .accessibilityLabel(
                    "\(String(localized: "Transcript language")), \(language)"
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func transcriptTypeHeader(_ type: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(String(localized: "Transcript type"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 8)

                Button {
                    copyTranscriptType(type)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel(String(localized: "Copy transcript type"))
                .accessibilityHint(
                    String(localized: "Copies the exact displayed transcript type to the pasteboard")
                )

                ShareLink(item: type) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(String(localized: "Share transcript type"))
                .accessibilityHint(
                    String(localized: "Shares the exact displayed transcript type as plain text")
                )
            }

            Text(type)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(2)
                .accessibilityLabel(
                    "\(String(localized: "Transcript type")), \(type)"
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .accessibilityElement(children: .contain)
    }

    private func copyTranscriptLanguage(_ language: String) {
        UIPasteboard.general.string = language
        copiedAlertMessage = String(localized: "Transcript language copied to the pasteboard.")
        copyFeedbackTick &+= 1
        showCopiedAlert = true
    }

    private func copyTranscriptType(_ type: String) {
        UIPasteboard.general.string = type
        copiedAlertMessage = String(localized: "Transcript type copied to the pasteboard.")
        copyFeedbackTick &+= 1
        showCopiedAlert = true
    }

    private func copyTranscriptURL(_ rawURL: String) {
        UIPasteboard.general.string = rawURL
        copiedAlertMessage = String(localized: "Transcript URL copied to the pasteboard.")
        copyFeedbackTick &+= 1
        showCopiedAlert = true
    }

    private func copyTranscript() {
        let text = transcriptPlainForCopy
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        copiedAlertMessage = String(localized: "Transcript copied to the pasteboard.")
        copyFeedbackTick += 1
        showCopiedAlert = true
    }

    private func copyCurrentCue() {
        guard let text = currentCuePlainForCopy, !text.isEmpty else { return }
        UIPasteboard.general.string = text
        copiedAlertMessage = String(localized: "Current cue copied to the pasteboard.")
        copyFeedbackTick += 1
        showCopiedAlert = true
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
