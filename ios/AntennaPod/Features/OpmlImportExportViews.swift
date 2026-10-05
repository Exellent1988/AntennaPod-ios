import SwiftUI
import UIKit
import UniformTypeIdentifiers

extension UTType {
    /// OPML is often served as XML; accept both `.opml` and `.xml`.
    static var opml: UTType {
        UTType(filenameExtension: "opml") ?? .xml
    }
}

/// FileDocument wrapper so SwiftUI `fileExporter` can Save OPML into Files.
struct OpmlExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.opml, .xml] }
    static var writableContentTypes: [UTType] { [.opml, .xml] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Shared Import / Export controls used from Settings and Subscriptions.
/// OPML import/export plus AntennaPod-style HTML export lite (subscriptions).
struct OpmlImportExportSection: View {
    @EnvironmentObject private var store: PodcastStore
    @EnvironmentObject private var parental: ParentalControls
    @State private var showImporter = false
    /// Settings and the Subscriptions OPML sheet gate Import OPML with the same Add/Discover PIN when locked.
    @State private var showImportPINGate = false
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var showImportResult = false
    @State private var exportError: String?
    @State private var exportDocument = OpmlExportDocument(data: Data())
    @State private var showFileExporter = false
    @State private var exportDefaultName = "AntennaPod-subscriptions"

    private var canExport: Bool {
        store.exportableSubscriptionCount > 0
    }

    var body: some View {
        Section {
            Button {
                exportOpmlShare()
            } label: {
                Label("Export OPML", systemImage: "square.and.arrow.up")
            }
            .disabled(!canExport)
            .accessibilityLabel(String(localized: "Export OPML"))
            .accessibilityHint(String(localized: "Opens the system share sheet with AntennaPod-compatible OPML 2.0. Local folder podcasts are omitted. You can Save to Files from the share sheet. Does not unsubscribe, import, or change tags. Distinct from Save OPML to Files… and HTML export."))

            Button {
                prepareSaveOpmlToFiles()
            } label: {
                Label("Save OPML to Files…", systemImage: "folder")
            }
            .disabled(!canExport)
            .accessibilityLabel(String(localized: "Save OPML to Files…"))
            .accessibilityHint(String(localized: "Opens the Files save picker and writes AntennaPod-compatible OPML. Local folder podcasts are omitted."))

            Button {
                exportHtml()
            } label: {
                Label("Export subscriptions as HTML", systemImage: "doc.richtext")
            }
            .disabled(!canExport)
            .accessibilityLabel(String(localized: "Export subscriptions as HTML"))
            .accessibilityHint(String(localized: "Shares a self-contained HTML subscription list via the system share sheet. Local folder podcasts are omitted. Author, language, categories, and funding appear only when provided by each feed."))

            Button {
                if parental.needsPINForAddDiscover {
                    showImportPINGate = true
                } else {
                    showImporter = true
                }
            } label: {
                Label("Import OPML", systemImage: "square.and.arrow.down")
            }
            .disabled(store.opmlImport.isImporting)
            .accessibilityLabel(
                parental.needsPINForAddDiscover
                    ? String(localized: "Import OPML (PIN required)")
                    : String(localized: "Import OPML")
            )
            .accessibilityHint(
                parental.needsPINForAddDiscover
                    ? String(localized: "Asks for the parental PIN, then opens Files to pick an .opml or .xml subscription list. Already subscribed feeds are skipped; each new feed is fetched over the network. Export OPML stays unlocked.")
                    : String(localized: "Opens Files to pick an .opml or .xml subscription list. Already subscribed feeds are skipped; each new feed is fetched over the network.")
            )

            if store.opmlImport.isImporting {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: store.opmlImport.fraction)
                    Text(progressLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "OPML import in progress"))
                .accessibilityValue(progressLabel)
            } else if store.opmlImport.total > 0 {
                Button {
                    showImportResult = true
                } label: {
                    Text(store.opmlImport.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(store.opmlImport.summary)
                .accessibilityHint(String(localized: "Shows added, already subscribed, and failed counts from the last OPML import."))
            }

            if let exportError {
                Text(exportError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let err = store.opmlImportError, !store.opmlImport.isImporting {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Import / Export")
        } footer: {
            Text(opmlHonestyFooter)
                .accessibilityLabel(opmlHonestyFooter)
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.opml, .xml, .data],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .fileExporter(
            isPresented: $showFileExporter,
            document: $exportDocument,
            contentType: .opml,
            defaultFilename: exportDefaultName
        ) { result in
            handleFileExport(result)
        }
        .sheet(isPresented: $showShare) {
            if let shareURL {
                ActivityView(items: [shareURL])
            }
        }
        .sheet(isPresented: $showImportResult) {
            OpmlImportResultView()
        }
        .sheet(isPresented: $showImportPINGate) {
            ParentalPINPromptSheet(
                title: String(localized: "Parental controls"),
                message: String(localized: "Enter your PIN to add or discover podcasts."),
                onCancel: { showImportPINGate = false },
                onSuccess: { pin in
                    if parental.unlockSession(with: pin) {
                        showImportPINGate = false
                        showImporter = true
                        return true
                    }
                    return false
                }
            )
        }
        .onChange(of: store.opmlImport.isImporting) { _, importing in
            if !importing, store.opmlImport.total > 0 {
                showImportResult = true
            }
        }
    }

    private var opmlHonestyFooter: String {
        let n = store.exportableSubscriptionCount
        let local = store.feeds.count - n
        var text = String(localized: "Import picks an .opml or .xml from Files (document picker). Already subscribed feed URLs are skipped; each new feed is fetched over the network. Export writes AntennaPod-compatible OPML 2.0 — Share sheet or Save to Files. Local folder podcasts are omitted from OPML and HTML. HTML lists title, feed URL, and episode count; author, language, categories, and funding only when the feed provides them. No cloud sync.")
        if local > 0 {
            text += " " + String(localized: "\(n) of \(store.feeds.count) subscriptions are exportable.")
        }
        return text
    }

    private var progressLabel: String {
        let s = store.opmlImport
        let base = "\(s.completed)/\(s.total)"
        if let title = s.currentTitle {
            return "\(base) — \(title)"
        }
        return base
    }

    private func exportOpmlShare() {
        exportError = nil
        do {
            let url = try store.exportOpmlTemporaryFile()
            shareURL = url
            showShare = true
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func prepareSaveOpmlToFiles() {
        exportError = nil
        do {
            let data = try store.exportOpmlData()
            exportDocument = OpmlExportDocument(data: data)
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyyMMdd-HHmmss"
            exportDefaultName = "AntennaPod-subscriptions-\(f.string(from: Date()))"
            showFileExporter = true
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func handleFileExport(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            exportError = nil
        case .failure(let error):
            if (error as? CocoaError)?.code == .userCancelled {
                return
            }
            let ns = error as NSError
            if ns.domain == NSCocoaErrorDomain, ns.code == NSUserCancelledError {
                return
            }
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
            store.opmlImportError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                }
                do {
                    let data = try Data(contentsOf: url)
                    await store.importOpml(data: data, sourceFileName: url.lastPathComponent)
                } catch {
                    store.opmlImportError = error.localizedDescription
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
                if let name = store.opmlImport.sourceFileName, !name.isEmpty {
                    Section {
                        LabeledContent("File", value: name)
                    }
                }
                Section {
                    LabeledContent("Added", value: "\(store.opmlImport.succeeded)")
                    LabeledContent("Already subscribed", value: "\(store.opmlImport.skipped)")
                    LabeledContent("Failed", value: "\(store.opmlImport.failures.count)")
                } footer: {
                    Text("Added feeds were fetched over the network. Already subscribed URLs were skipped. Failed rows list per-feed errors — the batch did not stop early.")
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
                            .accessibilityElement(children: .ignore)
                                .accessibilityLabel(failureAccessibilityLabel(for: failure))
                                .accessibilityValue(failureAccessibilityValue(for: failure))
                                .accessibilityHint(String(localized: "This feed was not added during the OPML import."))
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

    private func failureAccessibilityLabel(for failure: OpmlImportFailure) -> String {
        let title = failure.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return String(localized: "Failed OPML feed")
        }
        return String(localized: "Failed OPML feed \(title)")
    }

    private func failureAccessibilityValue(for failure: OpmlImportFailure) -> String {
        String(localized: "URL \(failure.url). Error \(failure.error)")
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
