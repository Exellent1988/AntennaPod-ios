import SwiftUI

/// Settings → About: fork identity, version, and contribute / project links (opens in Safari).
struct AboutView: View {
    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        let trimmedShort = short?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedBuild = build?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedShort.isEmpty {
            if !trimmedBuild.isEmpty, trimmedBuild != trimmedShort {
                return "\(trimmedShort) (\(trimmedBuild))"
            }
            return trimmedShort
        }
        return "0.1.0-beta (placeholder)"
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("AntennaPod iOS")
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Unofficial SwiftUI fork of the open-source AntennaPod podcast app. Local-first beta: subscribe, play, download, and manage your library on device.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            String(localized: "Unofficial SwiftUI fork of the open-source AntennaPod podcast app. Local-first beta: subscribe, play, download, and manage your library on device.")
                        )
                }
                .padding(.vertical, 4)
            }

            Section("Version") {
                LabeledContent("App version") {
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Text("Version comes from the app bundle when set (CFBundleShortVersionString); otherwise a beta placeholder is shown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Links") {
                aboutLink(
                    title: "AntennaPod website",
                    subtitle: "antennapod.org",
                    systemImage: "globe",
                    url: URL(string: "https://antennapod.org")!
                )
                aboutLink(
                    title: "AntennaPod on GitHub",
                    subtitle: "github.com/AntennaPod/AntennaPod",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    url: URL(string: "https://github.com/AntennaPod/AntennaPod")!
                )
                aboutLink(
                    title: "Contribute",
                    subtitle: "antennapod.org/contribute",
                    systemImage: "heart",
                    url: URL(string: "https://antennapod.org/contribute/")!
                )
                aboutLink(
                    title: "Documentation",
                    subtitle: "antennapod.org/documentation",
                    systemImage: "book",
                    url: URL(string: "https://antennapod.org/documentation/")!
                )
                aboutLink(
                    title: "This iOS fork",
                    subtitle: "github.com/Exellent1988/AntennaPod-ios",
                    systemImage: "iphone",
                    url: URL(string: "https://github.com/Exellent1988/AntennaPod-ios")!
                )
            }

            Section {
                Text("AntennaPod is free and open source. This iOS build is a community fork for beta exploration — not an official App Store release from the AntennaPod project.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        String(localized: "AntennaPod is free and open source. This iOS build is a community fork for beta exploration — not an official App Store release from the AntennaPod project.")
                    )
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func aboutLink(title: LocalizedStringKey, subtitle: String, systemImage: String, url: URL) -> some View {
        Link(destination: url) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: systemImage)
            }
        }
        .accessibilityHint(String(localized: "Opens this link in Safari"))
    }
}
