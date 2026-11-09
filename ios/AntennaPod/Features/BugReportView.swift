import OSLog
import SwiftUI
import UIKit

/// Android BugReportActivity (Settings → Report bug): device/app info plus the recent log,
/// Copy to clipboard, Export logs (share) and Open issue tracker. iOS reads this process's
/// unified log via `OSLogStore` and shows the **redacted** text (`BugReportRedactor`) as the
/// preview, so what the user sees is exactly what is copied or shared.
/// Issue tracker: this fork's GitHub issues (iOS bugs are not upstream Android bugs).
struct BugReportView: View {
    static let issueTrackerURL = URL(string: "https://github.com/Exellent1988/AntennaPod-ios/issues")!

    @State private var report: String?
    @State private var copied = false

    var body: some View {
        List {
            Section {
                Text("Please describe the problem in the issue tracker and attach this report. Passwords, tokens, gpodder credentials, auth headers and secrets in URLs are removed below.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button {
                    UIPasteboard.general.string = report
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy to clipboard", systemImage: "doc.on.doc")
                }
                .disabled(report == nil)
                if let report {
                    ShareLink(item: report, subject: Text("AntennaPod iOS bug report")) {
                        Label("Export logs", systemImage: "square.and.arrow.up")
                    }
                }
                Link(destination: Self.issueTrackerURL) {
                    Label("Open issue tracker", systemImage: "ladybug")
                }
            }
            Section("Report preview") {
                if let report {
                    Text(report)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .accessibilityIdentifier("bugReport.preview")
                } else {
                    ProgressView()
                }
            }
        }
        .navigationTitle("Report bug")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard report == nil else { return }
            let raw = await Task.detached(priority: .utility) { BugReportBuilder.rawReport() }.value
            report = BugReportRedactor.redact(raw, knownSecrets: BugReportBuilder.knownSecrets())
        }
    }
}

enum BugReportBuilder {
    /// Max log lines (newest kept), roughly Android's crash log + logcat tail.
    static let maxLogLines = 500

    static func environmentInfo() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        var sys = utsname()
        uname(&sys)
        let model = withUnsafePointer(to: &sys.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        return """
        ## Environment
        App version: \(version) (\(build))
        Bundle: \(Bundle.main.bundleIdentifier ?? "?")
        OS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Device: \(model)
        Locale: \(Locale.current.identifier)
        """
    }

    static func recentLog(since: TimeInterval = 3600) -> String {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else {
            return "(log unavailable)"
        }
        let start = store.position(date: Date().addingTimeInterval(-since))
        let fmt = ISO8601DateFormatter()
        var lines: [String] = []
        if let entries = try? store.getEntries(at: start) {
            for case let e as OSLogEntryLog in entries {
                lines.append("\(fmt.string(from: e.date)) [\(e.category)] \(e.composedMessage)")
                if lines.count > maxLogLines * 2 { lines.removeFirst(maxLogLines) }
            }
        }
        if lines.isEmpty { return "(no log entries)" }
        return lines.suffix(maxLogLines).joined(separator: "\n")
    }

    static func rawReport() -> String {
        environmentInfo() + "\n\n## Recent log (this app, last hour)\n" + recentLog()
    }

    /// Literal secrets stored on this device, removed wherever they appear.
    static func knownSecrets() -> [String] {
        [
            GpodderKeychain.loadPassword(),
            UserDefaults.standard.string(forKey: "gpodder.username"), // GpodderSyncService.Keys.username,
            PodcastIndexKeychain.loadAPIKey(),
            PodcastIndexKeychain.loadAPISecret(),
        ].compactMap { $0 }
    }
}
