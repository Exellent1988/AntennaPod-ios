import SwiftUI

/// Small chapter `img` thumbnail for chapter list rows.
///
/// - Shows only when an http(s) URL is provided (PSC / Podcast Index).
/// - On load failure or missing URL: **empty** — never episode / feed artwork placeholder.
/// - Lazy per visible cell via `AppAsyncImage` (AppURLSession; respects HTTP proxy) — does **not** download all chapter images eagerly.
/// - VoiceOver: decorative here; parent row appends “Chapter image” only after a successful load.
struct ChapterImageThumbnail: View {
    let url: URL?
    @Binding var didLoad: Bool
    var size: CGFloat = 36

    var body: some View {
        if let url {
            AppAsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .task(id: url) { didLoad = true }
                case .failure:
                    Color.clear
                        .task(id: url) { didLoad = false }
                case .empty:
                    ZStack {
                        Color.clear
                        ProgressView()
                            .controlSize(.mini)
                    }
                @unknown default:
                    Color.clear
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityHidden(true)
            .onChange(of: url) { _, _ in
                didLoad = false
            }
            .onDisappear {
                didLoad = false
            }
        }
    }
}
