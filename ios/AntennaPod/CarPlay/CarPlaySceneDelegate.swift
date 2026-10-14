import CarPlay
import UIKit

/// CarPlay audio app: tab bar with Subscriptions / Queue / Downloads, episode lists, Now Playing.
/// Requires the `com.apple.developer.carplay-audio` entitlement (Apple-granted) to appear in CarPlay.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        Task { @MainActor in
            let tabs = CPTabBarTemplate(templates: [
                self.subscriptionsTemplate(), self.queueTemplate(), self.downloadsTemplate(),
            ])
            interfaceController.setRootTemplate(tabs, animated: false, completion: nil)
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
    }

    // MARK: Templates

    @MainActor private func subscriptionsTemplate() -> CPListTemplate {
        let feeds = AppServices.store?.feeds ?? []
        let items = CarPlayBrowseModel.subscriptionRows(feeds).map(listItem)
        let t = CPListTemplate(title: String(localized: "Subscriptions"), sections: [CPListSection(items: items)])
        t.tabImage = UIImage(systemName: "square.stack")
        t.emptyViewTitleVariants = [String(localized: "No subscriptions")]
        return t
    }

    @MainActor private func queueTemplate() -> CPListTemplate {
        let store = AppServices.store
        let rows = CarPlayBrowseModel.queueRows(store?.queue ?? []) { [weak store] ep in
            store?.feeds.first(where: { $0.episodes.contains(where: { $0.id == ep.id }) })?.title
        }
        let t = CPListTemplate(title: String(localized: "Queue"), sections: [CPListSection(items: rows.map(listItem))])
        t.tabImage = UIImage(systemName: "list.bullet")
        t.emptyViewTitleVariants = [String(localized: "Queue is empty")]
        return t
    }

    @MainActor private func downloadsTemplate() -> CPListTemplate {
        let feeds = AppServices.store?.feeds ?? []
        let downloads = AppServices.downloads
        let rows = CarPlayBrowseModel.downloadRows(feeds: feeds) { downloads?.isDownloaded($0) ?? false }
        let t = CPListTemplate(title: String(localized: "Downloads"), sections: [CPListSection(items: rows.map(listItem))])
        t.tabImage = UIImage(systemName: "arrow.down.circle")
        t.emptyViewTitleVariants = [String(localized: "No downloads")]
        return t
    }

    @MainActor private func episodesTemplate(feedId: UUID) -> CPListTemplate {
        let feed = AppServices.store?.feeds.first { $0.id == feedId }
        let rows = CarPlayBrowseModel.episodeRows(feed?.episodes ?? [])
        return CPListTemplate(title: feed?.title ?? "", sections: [CPListSection(items: rows.map(listItem))])
    }

    @MainActor private func listItem(_ row: CarPlayRow) -> CPListItem {
        let item = CPListItem(text: row.title, detailText: row.detail)
        switch row.target {
        case .feed(let id):
            item.accessoryType = .disclosureIndicator
            item.handler = { [weak self] _, completion in
                Task { @MainActor in
                    guard let self else { completion(); return }
                    self.interfaceController?.pushTemplate(self.episodesTemplate(feedId: id), animated: true, completion: nil)
                    completion()
                }
            }
        case .episode(let id):
            if let playing = AppServices.playback?.currentEpisode?.id, playing == id {
                item.isPlaying = true
            }
            item.handler = { [weak self] _, completion in
                Task { @MainActor in
                    self?.play(episodeId: id)
                    completion()
                }
            }
        }
        return item
    }

    // MARK: Playback

    @MainActor private func play(episodeId: String) {
        guard let store = AppServices.store, let playback = AppServices.playback else { return }
        let episode = store.queue.first { $0.id == episodeId }
            ?? store.feeds.lazy.flatMap(\.episodes).first { $0.id == episodeId }
        guard let episode else { return }
        let fileURL = AppServices.downloads?.localURL(for: episode)
        guard playback.play(episode: episode, fileURL: fileURL) else { return }
        // System Now Playing is already fed by PlaybackService (MPNowPlayingInfoCenter + remotes).
        let nowPlaying = CPNowPlayingTemplate.shared
        if interfaceController?.topTemplate !== nowPlaying {
            interfaceController?.pushTemplate(nowPlaying, animated: true, completion: nil)
        }
    }
}
