import SwiftUI
import UniformTypeIdentifiers

/// Settings → Backup: export / import iOS JSON Application Support backup (beta); optional offline media.
struct DataBackupSection: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var downloads: DownloadService
    @EnvironmentObject private var gpodder: GpodderSyncService

    @State private var includeDownloadedMedia = false
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var showImporter = false
    @State private var showReplaceConfirm = false
    @State private var showExportMediaConfirm = false
    @State private var pendingImportURL: URL?
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var isBusy = false

    var body: some View {
        Section {
            Toggle(isOn: $includeDownloadedMedia) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Include downloaded episode files")
                    Text(mediaToggleCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .disabled(isBusy)
            .accessibilityLabel(String(localized: "Include downloaded episode files"))
            .accessibilityValue(includeDownloadedMedia ? String(localized: "On") : String(localized: "Off"))
            .accessibilityHint(mediaToggleCaption)

            Button {
                requestExport()
            } label: {
                Label("Export data backup", systemImage: "externaldrive.badge.timemachine")
            }
            .disabled(isBusy)
            .accessibilityLabel(String(localized: "Export data backup"))
            .accessibilityHint(String(localized: "Creates an iOS JSON backup ZIP and opens the system share sheet. Optional downloaded media is controlled above."))

            Button {
                errorMessage = nil
                statusMessage = nil
                showImporter = true
            } label: {
                Label("Import data backup", systemImage: "square.and.arrow.down.on.square")
            }
            .disabled(isBusy)
            .accessibilityLabel(String(localized: "Import data backup"))
            .accessibilityHint(String(localized: "Opens a file picker. The selected backup replaces local catalog data only after confirmation; Keychain secrets stay unchanged."))

            if isBusy {
                ProgressView("Working…")
                    .accessibilityLabel(String(localized: "Working…"))
                    .accessibilityValue(String(localized: "Backup operation in progress"))
            }
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(statusMessage)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(String(localized: "Backup error: \(errorMessage)"))
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
            .accessibilityHint(String(localized: "Replaces the local catalog and preferences with the selected backup. This cannot be undone except by importing another backup."))
            Button("Cancel", role: .cancel) {
                clearPendingImportAccess()
            }
        } message: {
            Text(importConfirmMessage)
        }
        .confirmationDialog(
            "Include media in this export?",
            isPresented: $showExportMediaConfirm,
            titleVisibility: .visible
        ) {
            Button("Export with media") {
                exportBackup(includeMedia: true)
            }
            .accessibilityHint(String(localized: "Includes the estimated offline episode files in the backup ZIP. Export and sharing may take longer."))
            Button("Export without media") {
                includeDownloadedMedia = false
                exportBackup(includeMedia: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(exportMediaConfirmMessage)
        }
    }

    private var mediaEstimate: (fileCount: Int, bytes: Int64) {
        DataBackupService.estimateMediaPayload()
    }

    private var mediaToggleCaption: String {
        let est = mediaEstimate
        if est.fileCount == 0 {
            return String(localized: "Default off — keeps the ZIP small (JSON catalog only). No offline files on device right now.")
        }
        let size = DataBackupService.formatBytes(est.bytes)
        return String(localized: "Default off — keeps the ZIP small. On: adds ~\(est.fileCount) file(s) (~\(size)) under downloads/ — larger ZIP, slower export/share/import (STORE, no compression).")
    }

    private var exportMediaConfirmMessage: String {
        let est = mediaEstimate
        let size = DataBackupService.formatBytes(est.bytes)
        return String(localized: "This will pack \(est.fileCount) offline episode file(s) (~\(size)) into the ZIP under downloads/. Export and sharing can take a long time and use a lot of storage. Keychain secrets are still omitted.")
    }

    private var importConfirmMessage: String {
        String(localized: "This replaces subscriptions, queue, playback, favorites, archive, bookmarks, tags, feed settings, download catalog, and Settings prefs with the backup. If the ZIP includes downloads/, those episode files are written into Documents/downloads (same names overwritten; other local files are left). Catalog-only backups still need re-download for missing media. Keychain passwords/keys are not replaced. This cannot be undone except by importing another backup.")
    }

    private var helpText: String {
        String(localized: "Beta iOS JSON backup (Application Support maps + Settings + gpodder prefs). Not AntennaPod Android DB. Optional offline media via the toggle (ZIP folder downloads/ ↔ Documents/downloads). gpodder password, Podcast Index keys, and per-feed HTTP Basic passwords stay in Keychain and are omitted from the ZIP. For a printable subscription list, use Import / Export → Export subscriptions as HTML.")
    }

    private func requestExport() {
        errorMessage = nil
        statusMessage = nil
        if includeDownloadedMedia {
            let est = mediaEstimate
            if est.fileCount > 0 {
                showExportMediaConfirm = true
                return
            }
        }
        exportBackup(includeMedia: includeDownloadedMedia)
    }

    private func exportBackup(includeMedia: Bool) {
        errorMessage = nil
        statusMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            let url = try DataBackupService.exportTemporaryZip(
                settings: settings,
                gpodder: gpodder,
                includeMedia: includeMedia
            )
            shareURL = url
            showShare = true
            if includeMedia {
                let est = mediaEstimate
                statusMessage = "Backup ready (JSON + \(est.fileCount) media file(s) under downloads/; no Keychain secrets)."
            } else {
                statusMessage = "Backup ready to share (JSON ZIP, no media / no Keychain secrets)."
            }
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
            statusMessage = "Import finished. Media restored when present under downloads/ in the ZIP; otherwise re-download offline files. Re-enter gpodder / Podcast Index / per-feed HTTP Basic secrets if Keychain empty."
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
