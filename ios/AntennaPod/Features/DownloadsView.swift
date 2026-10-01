import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var downloads: DownloadService
    @EnvironmentObject private var playback: PlaybackService

    var body: some View {
        NavigationStack {
            List {
                if let error = downloads.lastError {
                    Section {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Last download failed")
                                    .font(.subheadline.weight(.semibold))
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let latest = downloads.recentErrors.first {
                                    Text(latest.episodeTitle)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                    if !latest.feedTitle.isEmpty {
                                        Text(latest.feedTitle)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                if downloads.downloads.isEmpty {
                    ContentUnavailableView(
                        "No downloads",
                        systemImage: "arrow.down.circle",
                        description: Text("Downloaded episodes will appear here for offline playback.")
                    )
                } else {
                    Section {
                        ForEach(downloads.downloads) { item in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.episode.title)
                                        .font(.headline)
                                    Text(item.localFileURL.lastPathComponent)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    playback.play(episode: item.episode)
                                } label: {
                                    Image(systemName: "play.fill")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                downloads.delete(downloads.downloads[index].episode)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Downloads")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        DownloadErrorsView()
                    } label: {
                        Label("Errors", systemImage: "exclamationmark.bubble")
                    }
                    .accessibilityLabel("Download errors")
                }
            }
        }
    }
}

/// Simple list of persisted download failures (ring buffer) with clear action.
struct DownloadErrorsView: View {
    @EnvironmentObject private var downloads: DownloadService
    @State private var showClearConfirmation = false

    var body: some View {
        List {
            if downloads.recentErrors.isEmpty {
                ContentUnavailableView(
                    "No download errors",
                    systemImage: "checkmark.circle",
                    description: Text("Failed downloads will appear here (up to \(DownloadService.downloadErrorRingCapacity) recent).")
                )
            } else {
                ForEach(downloads.recentErrors) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.episodeTitle.isEmpty ? "Unknown episode" : entry.episodeTitle)
                            .font(.headline)
                        if !entry.feedTitle.isEmpty {
                            Text(entry.feedTitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.message)
                            .font(.caption)
                            .foregroundStyle(.red)
                        Text(entry.timestamp, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle("Download errors")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear", role: .destructive) {
                    showClearConfirmation = true
                }
                .disabled(downloads.recentErrors.isEmpty && downloads.lastError == nil)
            }
        }
        .confirmationDialog(
            "Clear download errors?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear errors", role: .destructive) {
                downloads.clearDownloadErrors()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes the saved error log and the Downloads banner. Offline files are kept.")
        }
    }
}
