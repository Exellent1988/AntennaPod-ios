import SwiftUI
import UIKit

/// Phases match SwiftUI `AsyncImage` so call sites can switch with the same `switch`.
enum AppAsyncImagePhase {
    case empty
    case success(Image)
    case failure(Error)
}

/// Loads a remote image through `AppURLSession` (HTTP proxy + authenticated 407), unlike stock
/// `AsyncImage`, which uses `URLSession.shared` and bypasses Settings → HTTP proxy.
/// Lock-screen artwork already uses `AppURLSession`; Full Player / Discover / preview / chapter
/// thumbs used `AsyncImage` and stayed blank behind a required proxy.
struct AppAsyncImage<Content: View>: View {
    let url: URL?
    @ViewBuilder var content: (AppAsyncImagePhase) -> Content

    @State private var phase: AppAsyncImagePhase = .empty

    init(url: URL?, @ViewBuilder content: @escaping (AppAsyncImagePhase) -> Content) {
        self.url = url
        self.content = content
    }

    var body: some View {
        content(phase)
            .task(id: url?.absoluteString ?? "") {
                await load()
            }
    }

    @MainActor
    private func load() async {
        phase = .empty
        guard let url else { return }
        do {
            let (data, _) = try await AppURLSession.shared.data(from: url)
            try Task.checkCancellation()
            guard let uiImage = UIImage(data: data) else {
                phase = .failure(URLError(.cannotDecodeContentData))
                return
            }
            phase = .success(Image(uiImage: uiImage))
        } catch is CancellationError {
            // View went away or URL changed; leave phase for the next task.
        } catch {
            phase = .failure(error)
        }
    }
}
