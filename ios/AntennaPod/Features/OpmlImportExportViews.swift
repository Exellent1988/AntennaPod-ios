import SwiftUI
import UIKit
import UniformTypeIdentifiers

extension UTType {
    /// OPML is often served as XML; accept both `.opml` and `.xml`.
    static var opml: UTType {
        UTType(filenameExtension: "opml") ?? .xml
    }
}

/// Shared Import / Export controls used from Settings and Subscriptions.
/// OPML import/export plus AntennaPod-style HTML export lite (subscriptions).
struct OpmlImportExportSection: View {
    @EnvironmentObject private var store: PodcastStore
    @State private var showImporter = false
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var showImportResult = false
    @State private var exportError: String?

    var body: some View {
        Section("Import / Export") {
            Button {
                exportOpml()
            } label: {
                Label("Export OPML", systemImage: "square.and.arrow.up")
            }
            .disabled(store.feeds.isEmpty)

            Button {
                exportHtml()
            } label: {
                Label("Export subscriptions as HTML", systemImage: "doc.richtext")
            }
            .disabled(store.feeds.isEmpty)

            Button {
                showImporter = true
            } label: {
                Label("Import OPML", systemImage: "square.and.arrow.down")
            }
            .disabled(store.opmlImport.isImporting)

            if store.opmlImport.isImporting {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: store.opmlImport.fraction)
                    Text(progressLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if store.opmlImport.total > 0 {
                Button {
                    showImportResult = true
                } label: {
                    Text(store.opmlImport.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let exportError {
                Text(exportError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let err = store.lastError, !store.opmlImport.isImporting {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.opml, .xml, .data],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .sheet(isPresented: $showShare) {
            if let shareURL {
                ActivityView(items: [shareURL])
            }
        }
        .sheet(isPresented: $showImportResult) {
            OpmlImportResultView()
        }
        .onChange(of: store.opmlImport.isImporting) { _, importing in
            if !importing, store.opmlImport.total > 0 {
                showImportResult = true
            }
        }
    }

    private var progressLabel: String {
        let s = store.opmlImport
        let base = "\(s.completed)/\(s.total)"
        if let title = s.currentTitle {
            return "\(base) — \(title)"
        }
        return base
    }

    private func exportOpml() {
        exportError = nil
        do {
            let url = try store.exportOpmlTemporaryFile()
            shareURL = url
            showShare = true
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func exportHtml() {
        exportError = nil
        do {
            let url = try store.exportSubscriptionsHTMLTemporaryFile(includeEpisodeCount: true)
            shareURL = url
            showShare = true
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            store.lastError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                }
                do {
                    let data = try Data(contentsOf: url)
                    await store.importOpml(data: data)
                } catch {
                    store.lastError = error.localizedDescription
                }
            }
        }
    }
}

struct OpmlImportResultView: View {
    @EnvironmentObject private var store: PodcastStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Added", value: "\(store.opmlImport.succeeded)")
                    LabeledContent("Already subscribed", value: "\(store.opmlImport.skipped)")
                    LabeledContent("Failed", value: "\(store.opmlImport.failures.count)")
                }
                if !store.opmlImport.failures.isEmpty {
                    Section("Errors") {
                        ForEach(store.opmlImport.failures) { failure in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(failure.title)
                                    .font(.headline)
                                Text(failure.url)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(failure.error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
            .navigationTitle("OPML import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// UIKit share sheet bridge.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
