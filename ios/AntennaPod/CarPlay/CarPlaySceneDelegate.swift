import CarPlay
import Combine
import UIKit

/// CarPlay audio app mirroring the Android Auto browse tree (`PlaybackService.loadChildrenSynchronous`):
/// Queue (with a "Currently playing" section), Downloads, Episodes, Subscriptions → podcast episodes.
/// Lists update live (debounced) and show artwork, progress, and the playing indicator.
/// Requires the `com.apple.developer.carplay-audio` entitlement (Apple-granted) to appear in CarPlay.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPNowPlayingTemplateObserver {
    private var interfaceController: CPInterfaceController?
    private var tabs: [CarPlayTab: CPListTemplate] = [:]
    private var episodeLists: [(feedId: UUID, template: CPListTemplate)] = []
    private var rendered: [ObjectIdentifier: [[CarPlayRow]]] = [:]
    private var cancellables = Set<AnyCancellable>()

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        Task { @MainActor in
            var ordered: [CPListTemplate] = []
            for tab in CarPlayTab.allCases {
                let t = self.makeTemplate(tab)
                self.tabs[tab] = t
                ordered.append(t)
            }
            self.reloadAll()
            self.configureNowPlaying()
            interfaceController.setRootTemplate(CPTabBarTemplate(templates: ordered), animated: false, completion: nil)
            self.observeStores()
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        cancellables.removeAll()
        CPNowPlayingTemplate.shared.remove(self)
        episodeLists.removeAll()
        rendered.removeAll()
        tabs.removeAll()
        self.interfaceController = nil
    }

    // MARK: Live refresh

    @MainActor private func observeStores() {
        var signals: [AnyPublisher<Void, Never>] = []
        if let store = AppServices.store {
            signals.append(store.$feeds.map { _ in () }.eraseToAnyPublisher())
            signals.append(store.$queue.map { _ in () }.eraseToAnyPublisher())
            signals.append(store.$playbackStates.map { _ in () }.eraseToAnyPublisher())
            signals.append(store.$favoriteAtById.map { _ in () }.eraseToAnyPublisher())
            signals.append(store.$archivedAtById.map { _ in () }.eraseToAnyPublisher())
        }
        if let dl = AppServices.downloads {
            signals.append(dl.$downloads.map { _ in () }.eraseToAnyPublisher())
        }
        if let pb = AppServices.playback {
            signals.append(pb.$currentEpisode.map { $0?.id }.removeDuplicates().map { _ in () }.eraseToAnyPublisher())
        }
        if let settings = AppServices.settings {
            signals.append(settings.objectWillChange.map { _ in () }.eraseToAnyPublisher())
        }
        Publishers.MergeMany(signals)
            .debounce(for: .milliseconds(CarPlayBrowseModel.refreshDebounceMs), scheduler: RunLoop.main)
            .sink { [weak self] in MainActor.assumeIsolated { self?.reloadAll() } }
            .store(in: &cancellables)
    }

    @MainActor private var limit: Int { CarPlayParity.itemLimit(templateMax: Int(CPListTemplate.maximumItemCount)) }

    @MainActor private func reloadAll() {
        guard let store = AppServices.store else { return }
        let settings = AppServices.settings
        let all = allEpisodeInfos()
        let byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let playingId = AppServices.playback?.currentEpisode?.id

        if let t = tabs[.queue] {
            var sections: [(String?, [CarPlayRow])] = []
            if let pid = playingId, let cur = byId[pid] ?? AppServices.playback?.currentEpisode.map({ info($0, feed: nil) }) {
                sections.append((String(localized: "Currently playing"), [row(cur)]))
            }
            let q = store.queue.prefix(limit).map { byId[$0.id] ?? info($0, feed: nil) }
            sections.append((sections.isEmpty ? nil : String(localized: "Queue"), q.map { row($0) }))
            apply(sections, to: t)
        }
        if let t = tabs[.downloads] {
            let rows = CarPlayParity.downloads(all, sort: settings?.downloadsSort ?? .newestFirst, limit: limit).map { row($0) }
            apply([(nil, rows)], to: t)
        }
        if let t = tabs[.episodes] {
            let rows = CarPlayParity.episodes(
                all, filter: settings?.allEpisodesFilter ?? .all, sort: settings?.allEpisodesSort ?? .newestFirst, limit: limit
            ).map { row($0) }
            apply([(nil, rows)], to: t)
        }
        if let t = tabs[.subscriptions] {
            let unplayed = store.unplayedCountsByFeedId()
            let infos = store.feeds.map {
                CarPlayParity.FeedInfo(id: $0.id, title: store.displayTitle(for: $0), author: $0.author,
                                       unplayedCount: unplayed[$0.id] ?? 0, lastRefreshedEpochMs: $0.lastRefreshedAtEpochMs)
            }
            let feedsById = Dictionary(store.feeds.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let rows = CarPlayParity.feeds(infos, sort: settings?.subscriptionsSort ?? .alphabetical, limit: limit).map { f in
                let feed = feedsById[f.id]
                return CarPlayRow(
                    title: f.title,
                    detail: f.unplayedCount > 0 ? String(localized: "\(f.unplayedCount) unplayed") : f.author,
                    imageUrl: feed.flatMap { CarPlayBrowseModel.artworkURL($0.preferredDisplayArtworkURL, $0.imageUrl) },
                    target: .feed(f.id)
                )
            }
            apply([(nil, rows)], to: t)
        }
        let stack = interfaceController?.templates ?? []
        episodeLists.removeAll { entry in !stack.contains { $0 === entry.template } }
        for entry in episodeLists { apply([(nil, feedEpisodeRows(entry.feedId, byId: byId))], to: entry.template) }
    }

    // MARK: Building

    @MainActor private func info(_ ep: PodcastEpisode, feed: PodcastFeed?) -> CarPlayEpisodeInfo {
        let store = AppServices.store
        let dl = AppServices.downloads
        let item = dl?.downloads.first { $0.id == ep.id }
        return CarPlayEpisodeInfo(
            id: ep.id,
            title: ep.title,
            feedTitle: feed.map { store?.displayTitle(for: $0) ?? $0.title } ?? "",
            artwork: CarPlayBrowseModel.artworkURL(
                ep.preferredPodcastImagesArtworkURL, feed?.preferredDisplayArtworkURL, feed?.imageUrl),
            pubDateEpochMs: ep.pubDateEpochMs,
            durationSeconds: ep.durationSeconds,
            positionSeconds: store?.positionSeconds(for: ep.id) ?? 0,
            isPlayed: store?.isPlayed(ep.id) ?? false,
            isArchived: store?.isArchived(ep.id) ?? false,
            isFavorite: store?.isFavorite(ep.id) ?? false,
            isDownloaded: dl?.isDownloaded(ep) ?? false,
            downloadedAtEpochMs: item?.downloadedAtEpochMs,
            byteSize: item?.knownByteSize()
        )
    }

    @MainActor private func allEpisodeInfos() -> [CarPlayEpisodeInfo] {
        var seen = Set<String>()
        var out: [CarPlayEpisodeInfo] = []
        for feed in AppServices.store?.feeds ?? [] {
            for ep in feed.episodes where seen.insert(ep.id).inserted { out.append(info(ep, feed: feed)) }
        }
        return out
    }

    @MainActor private func feedEpisodeRows(_ feedId: UUID, byId: [String: CarPlayEpisodeInfo]) -> [CarPlayRow] {
        let feed = AppServices.store?.feeds.first { $0.id == feedId }
        let infos = (feed?.episodes ?? []).map { byId[$0.id] ?? info($0, feed: feed) }
        return CarPlayParity.sorted(infos, by: .newestFirst).prefix(limit).map { row($0, showFeed: false) }
    }

    private func row(_ e: CarPlayEpisodeInfo, showFeed: Bool = true) -> CarPlayRow {
        CarPlayRow(title: e.title, detail: CarPlayParity.detail(e, showFeed: showFeed), imageUrl: e.artwork,
                   target: .episode(e.id), progress: CarPlayParity.progress(e))
    }

    @MainActor private func apply(_ sections: [(String?, [CarPlayRow])], to template: CPListTemplate) {
        let key = ObjectIdentifier(template)
        let playingId = AppServices.playback?.currentEpisode?.id
        // Fold the playing marker into rows so indicator changes trigger an update.
        let marked = sections.map { $0.1.map { r -> CarPlayRow in
            var r = r
            if case .episode(let id) = r.target, id == playingId { r.detail = "▶︎" + (r.detail ?? "") }
            return r
        } }
        guard rendered[key] != marked else { return }
        rendered[key] = marked
        CarPlayArtworkLoader.shared.prefetch(CarPlayBrowseModel.uniqueArtworkURLs(sections.flatMap(\.1)))
        template.updateSections(sections.map { header, rows in
            CPListSection(items: rows.map { listItem($0, playingId: playingId) }, header: header, sectionIndexTitle: nil)
        })
    }

    // MARK: Templates

    @MainActor private func makeTemplate(_ tab: CarPlayTab) -> CPListTemplate {
        let spec: (String, String, String)
        switch tab {
        case .queue: spec = (String(localized: "Queue"), "list.bullet", String(localized: "Queue is empty"))
        case .downloads: spec = (String(localized: "Downloads"), "arrow.down.circle", String(localized: "No downloads"))
        case .episodes: spec = (String(localized: "Episodes"), "dot.radiowaves.up.forward", String(localized: "No episodes"))
        case .subscriptions: spec = (String(localized: "Subscriptions"), "square.stack", String(localized: "No subscriptions"))
        }
        let (title, icon, empty) = spec
        let t = CPListTemplate(title: title, sections: [])
        t.tabImage = UIImage(systemName: icon)
        t.emptyViewTitleVariants = [empty]
        return t
    }

    @MainActor private func pushEpisodes(feedId: UUID) {
        let store = AppServices.store
        let title = store?.displayTitle(forFeedId: feedId) ?? ""
        let t = CPListTemplate(title: title, sections: [])
        t.emptyViewTitleVariants = [String(localized: "No episodes")]
        apply([(nil, feedEpisodeRows(feedId, byId: [:]))], to: t)
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
            item.playingIndicatorLocation = .trailing
            item.playbackProgress = CGFloat(row.progress)
            item.handler = { [weak self] _, completion in
                Task { @MainActor in
                    self?.play(episodeId: id)
                    completion()
                }
            }
        }
        return item
    }

    // MARK: Now Playing

    /// Rate button (cycles Settings speed presets, like the app's speed chip) and Up Next → Queue.
    /// Skip ± buttons come from MPRemoteCommandCenter skip commands (Settings intervals).
    @MainActor private func configureNowPlaying() {
        let np = CPNowPlayingTemplate.shared
        np.add(self)
        np.isUpNextButtonEnabled = true
        np.upNextTitle = String(localized: "Up Next")
        np.isAlbumArtistButtonEnabled = false
        let rate = CPNowPlayingPlaybackRateButton { _ in
            Task { @MainActor in AppServices.playback?.cycleToNextSpeedPreset() }
        }
        np.updateNowPlayingButtons([rate])
    }

    func nowPlayingTemplateUpNextButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        Task { @MainActor in
            guard let store = AppServices.store else { return }
            let t = CPListTemplate(title: String(localized: "Up Next"), sections: [])
            t.emptyViewTitleVariants = [String(localized: "Queue is empty")]
            let currentId = AppServices.playback?.currentEpisode?.id
            let upcoming = CarPlayParity.upNext(queueIds: store.queue.map(\.id), currentId: currentId)
            let byId = Dictionary(store.queue.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let rows = upcoming.prefix(self.limit).compactMap { byId[$0] }.map {
                self.row(self.info($0, feed: store.feed(containingEpisodeId: $0.id)))
            }
            self.apply([(nil, rows)], to: t)
            self.interfaceController?.pushTemplate(t, animated: true, completion: nil)
        }
    }

    func nowPlayingTemplateAlbumArtistButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {}

    // MARK: Playback

    @MainActor private func play(episodeId: String) {
        guard let store = AppServices.store, let playback = AppServices.playback else { return }
        let episode = (playback.currentEpisode?.id == episodeId ? playback.currentEpisode : nil)
            ?? store.queue.first { $0.id == episodeId }
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
