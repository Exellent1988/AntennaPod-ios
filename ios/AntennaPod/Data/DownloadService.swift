import Foundation

struct DownloadedEpisode: Identifiable, Hashable {
    var id: String { episode.id }
    let episode: PodcastEpisode
    let localFileURL: URL
}

@MainActor
final class DownloadService: ObservableObject {
    @Published var downloads: [DownloadedEpisode] = []
    @Published var inProgress: Set<String> = []
    @Published var lastError: String?

    private let directory: URL = {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func localURL(for episode: PodcastEpisode) -> URL? {
        downloads.first(where: { $0.id == episode.id })?.localFileURL
    }

    func isDownloaded(_ episode: PodcastEpisode) -> Bool {
        localURL(for: episode) != nil
    }

    func download(_ episode: PodcastEpisode) async {
        guard let remote = episode.downloadUrl, let url = URL(string: remote) else {
            lastError = "Episode has no media URL"
            return
        }
        lastError = nil
        inProgress.insert(episode.id)
        defer { inProgress.remove(episode.id) }
        do {
            let (tempURL, response) = try await URLSession.shared.download(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            let ext = url.pathExtension.isEmpty ? "mp3" : url.pathExtension
            let safeName = episode.id
                .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
            let destination = directory.appendingPathComponent("\(safeName).\(ext)")
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)
            downloads.removeAll { $0.id == episode.id }
            downloads.append(DownloadedEpisode(episode: episode, localFileURL: destination))
        } catch {
            lastError = error.localizedDescription
        }
    }

    func delete(_ episode: PodcastEpisode) {
        if let existing = downloads.first(where: { $0.id == episode.id }) {
            try? FileManager.default.removeItem(at: existing.localFileURL)
            downloads.removeAll { $0.id == episode.id }
        }
    }
}
