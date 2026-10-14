import CarPlay
import Combine
import UIKit

/// CarPlay audio app: tab bar with Subscriptions / Queue / Downloads, episode lists, Now Playing.
/// Lists update live (debounced) when feeds, queue, downloads, or the current episode change.
/// Requires the `com.apple.developer.carplay-audio` entitlement (Apple-granted) to appear in CarPlay.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var subscriptions: CPListTemplate?
    private var queue: CPListTemplate?
    private var downloads: CPListTemplate?
    /// Pushed podcast episode lists, keyed by template identity.
    private var episodeLists: [(feedId: UUID, template: CPListTemplate)] = []
    /// Last rendered rows per template, to skip no-op updateSections.
    private var rendered: [ObjectIdentifier: CarPlayListSnapshot] = [:]
    private var cancellables = Set<AnyCancellable>()

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        Task { @MainActor in
            let subs = self.makeTemplate(title: String(localized: "Subscriptions"), icon: "square.stack", empty: String(localized: "No subscriptions"))
            let queue = self.makeTemplate(title: String(localized: "Queue"), icon: "list.bullet", empty: String(localized: "Queue is empty"))
            let dls = self.makeTemplate(title: String(localized: "Downloads"), icon: "arrow.down.circle", empty: String(localized: "No downloads"))
            self.subscriptions = subs; self.queue = queue; self.downloads = dls
            self.reloadAll()
            interfaceController.setRootTemplate(CPTabBarTemplate(templates: [subs, queue, dls]), animated: false, completion: nil)
            self.observeStores()
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        cancellables.removeAll()
        episodeLists.removeAll()
        rendered.removeAll()
        subscriptions = nil; queue = nil; downloads = nil
        self.interfaceController = nil
    }

    // MARK: Live refresh

    @MainActor private func observeStores() {
        var signals: [AnyPublisher<Void, Never>] = []
        if let store = AppServices.store {
            signals.append(store.$feeds.map { _ in () }.eraseToAnyPublisher())
            signals.append(store.$queue.map { _ in () }.eraseToAnyPublisher())
        }
        if let dl = AppServices.downloads {
            signals.append(dl.$downloads.map { _ in () }.eraseToAnyPublisher())
        }
        if let pb = AppServices.playback {
            signals.append(pb.$currentEpisode.map { $0?.id }.removeDuplicates().map { _ in () }.eraseToAnyPublisher())
        }
        Publishers.MergeMany(signals)
            .debounce(for: .milliseconds(CarPlayBrowseModel.refreshDebounceMs), scheduler: RunLoop.main)
            .sink { [weak self] in MainActor.assumeIsolated { self?.reloadAll() } }
            .store(in: &cancellables)
    }

    @MainActor private func reloadAll() {
        guard let store = AppServices.store else { return }
        let dl = AppServices.downloads
        if let t = subscriptions { apply(CarPlayBrowseModel.subscriptionRows(store.feeds), to: t) }
        if let t = queue {
            apply(CarPlayBrowseModel.queueRows(store.queue) { ep in
                store.feeds.first { $0.episodes.contains { $0.id == ep.id } }
            }, to: t)
        }
        if let t = downloads {
            apply(CarPlayBrowseModel.downloadRows(feeds: store.feeds) { dl?.isDownloaded($0) ?? false }, to: t)
        }
        // Drop lists no longer on the stack; refresh the rest.
        let stack = interfaceController?.templates ?? []
        episodeLists.removeAll { entry in !stack.contains { $0 === entry.template } }
        for entry in episodeLists { apply(episodeRows(feedId: entry.feedId), to: entry.template) }
    }

    @MainActor private func apply(_ rows: [CarPlayRow], to template: CPListTemplate) {
        let key = ObjectIdentifier(template)
        let playingId = AppServices.playback?.currentEpisode?.id
        let snapshot = CarPlayListSnapshot(rows: rows, playingEpisodeId: playingId)
        guard rendered[key] != snapshot else { return }
        rendered[key] = snapshot
        template.updateSections([CPListSection(items: rows.map { listItem($0, playingId: playingId) })])
    }

    // MARK: Templates

    @MainActor private func makeTemplate(title: String, icon: String, empty: String) -> CPListTemplate {
        let t = CPListTemplate(title: title, sections: [])
        t.tabImage = UIImage(systemName: icon)
        t.emptyViewTitleVariants = [empty]
        return t
    }

    @MainActor private func episodeRows(feedId: UUID) -> [CarPlayRow] {
        let feed = AppServices.store?.feeds.first { $0.id == feedId }
        return CarPlayBrowseModel.episodeRows(
            feed?.episodes ?? [],
            feedArtwork: feed.flatMap { CarPlayBrowseModel.artworkURL($0.preferredDisplayArtworkURL, $0.imageUrl) }
        )
    }

    @MainActor private func pushEpisodes(feedId: UUID) {
        let title = AppServices.store?.feeds.first { $0.id == feedId }?.title ?? ""
        let t = CPListTemplate(title: title, sections: [])
        apply(episodeRows(feedId: feedId), to: t)
        episodeLists.append((feedId, t))
        interfaceController?.pushTemplate(t, animated: true, completion: nil)
    }

    @MainActor private func listItem(_ row: CarPlayRow, playingId: String?) -> CPListItem {
        let loader = CarPlayArtworkLoader.shared
        let cachedImage = row.imageUrl.flatMap { loader.cached($0) }
        let item = CPListItem(text: row.title, detailText: row.detail, image: cachedImage ?? CarPlayArtworkLoader.placeholder)
        if cachedImage == nil, let url = row.imageUrl {
            Task { @MainActor [weak item] in
                if let img = await loader.image(for: url) { item?.setImage(img) }
            }
        }
        switch row.target {
        case .feed(let id):
            item.accessoryType = .disclosureIndicator
            item.handler = { [weak self] _, completion in
                Task { @MainActor in
                    self?.pushEpisodes(feedId: id)
                    completion()
                }
            }
        case .episode(let id):
            item.isPlaying = (id == playingId)
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
