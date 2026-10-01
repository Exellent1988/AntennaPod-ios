import SwiftUI

/// Scrollable episode shownotes / description sheet (plain text; HTML stripped for beta).
struct EpisodeDescriptionSheetView: View {
    @Environment(\.dismiss) private var dismiss

    let episode: PodcastEpisode

    private var plainDescription: String {
        guard let raw = episode.descriptionText else { return "" }
        return HTMLTextStripping.plainText(from: raw)
    }

    var body: some View {
        NavigationStack {
            Group {
                if plainDescription.isEmpty {
                    ContentUnavailableView(
                        "No description",
                        systemImage: "doc.text",
                        description: Text("This episode has no shownotes in the feed.")
                    )
                } else {
                    ScrollView {
                        Text(plainDescription)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding()
                    }
                }
            }
            .navigationTitle("Shownotes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Plain text — HTML tags stripped")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.bar)
            }
        }
    }
}
