import SwiftUI
import UniformTypeIdentifiers

/// Settings → Backup: export / import iOS JSON Application Support backup (beta).
struct DataBackupSection: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var downloads: DownloadService
    @EnvironmentObject private var gpodder: GpodderSyncService

    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var showImporter = false
    @State private var showReplaceConfirm = false
    @State private var pendingImportURL: URL?
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var isBusy = false

    var body: some View {
        Section {
            Button {
                exportBackup()
            } label: {
                Label("Export data backup", systemImage: "externaldrive.badge.timemachine")
            }
            .disabled(isBusy)

            Button {
                errorMessage = nil
                statusMessage = nil
                showImporter = true
            } label: {
                Label("Import data backup", systemImage: "square.and.arrow.down.on.square")
            }
            .disabled(isBusy)

            if isBusy {
                ProgressView("Working…")
            }
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Text(helpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Backup")
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.zip, .data],
            allowsMultipleSelection: false
        ) { result in
            handleImportPick(result)
        }
        .sheet(isPresented: $showShare) {
            if let shareURL {
                ActivityView(items: [shareURL])
            }
        }
        .confirmationDialog(
            "Replace local data?",
            isPresented: $showReplaceConfirm,
            titleVisibility: .visible
        ) {
            Button("Replace & import", role: .destructive) {
                if let pendingImportURL {
                    performImport(from: pendingImportURL)
                }
            }
            Button("Cancel", role: .cancel) {
                clearPendingImportAccess()
            }
        } message: {
            Text("This replaces subscriptions, queue, playback, favorites, archive, tags, feed settings, download catalog, and Settings prefs with the backup. Download media files are not in the backup (re-download). Keychain passwords/keys are not replaced. This cannot be undone except by importing another backup.")
        }
    }

    private var helpText: String {
        "Beta iOS JSON backup (Application Support maps + Settings + gpodder prefs). Not AntennaPod Android DB. Catalog only for downloads — offline media not included. gpodder password and Podcast Index keys stay in Keychain and are omitted from the ZIP. For a printable subscription list, use Import / Export → Export subscriptions as HTML."
    }

    private func exportBackup() {
        errorMessage = nil
        statusMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            let url = try DataBackupService.exportTemporaryZip(settings: settings, gpodder: gpodder)
            shareURL = url
            showShare = true
            statusMessage = "Backup ready to share (JSON ZIP, no media / no Keychain secrets)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleImportPick(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            // Keep security-scoped access until import finishes or cancel.
            _ = url.startAccessingSecurityScopedResource()
            pendingImportURL = url
            showReplaceConfirm = true
        }
    }

    private func performImport(from url: URL) {
        errorMessage = nil
        statusMessage = nil
        isBusy = true
        defer {
            isBusy = false
            url.stopAccessingSecurityScopedResource()
            pendingImportURL = nil
        }
        do {
            // Copy to temp so we can release the security scope promptly after read.
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("import-\(UUID().uuidString).zip")
            if FileManager.default.fileExists(atPath: temp.path) {
                try FileManager.default.removeItem(at: temp)
            }
            try FileManager.default.copyItem(at: url, to: temp)
            try DataBackupService.importZip(
                from: temp,
                store: store,
                settings: settings,
                downloads: downloads,
                gpodder: gpodder
            )
            try? FileManager.default.removeItem(at: temp)
            statusMessage = "Import finished. Download media was not in the backup — re-download offline files if needed. Re-enter gpodder / Podcast Index secrets if Keychain empty."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearPendingImportAccess() {
        if let pendingImportURL {
            pendingImportURL.stopAccessingSecurityScopedResource()
        }
        pendingImportURL = nil
    }
}
